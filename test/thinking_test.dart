import 'package:flutter_test/flutter_test.dart';
import 'package:mnn_pocket_chat/core/models.dart';
import 'package:mnn_pocket_chat/core/thinking.dart';

void main() {
  group('splitThinking', () {
    test('成对标签：思考与正文正确分离', () {
      final parts = splitThinking('<think>先算一下 1+1</think>等于 2。');
      expect(parts.thinking, '先算一下 1+1');
      expect(parts.answer, '等于 2。');
      expect(parts.state, ThinkingState.done);
    });

    test('只有结束标签（chat template 已注入起始标签）', () {
      // 这是最常见的真实场景：prompt 里已有 <think>，模型只输出 </think>。
      final parts = splitThinking('用户问的是加法，我先确认数字。</think>答案是 2。');
      expect(parts.thinking, '用户问的是加法，我先确认数字。');
      expect(parts.answer, '答案是 2。');
      expect(parts.state, ThinkingState.done);
      expect(parts.hasThinking, isTrue);
    });

    test('起始标签未闭合：剩余内容全部归入思考，不外泄到正文', () {
      final parts = splitThinking('<think>我正在一步一步推理，但被 token 上限截断了');
      expect(parts.answer, isEmpty);
      expect(parts.thinking, contains('一步一步推理'));
      expect(parts.state, ThinkingState.thinking);
    });

    test('无任何标签：整段作为正文，绝不折叠答案', () {
      final parts = splitThinking('这就是直接给出的答案，没有任何推理标记。');
      expect(parts.thinking, isEmpty);
      expect(parts.answer, '这就是直接给出的答案，没有任何推理标记。');
      expect(parts.state, ThinkingState.none);
      expect(parts.hasThinking, isFalse);
    });

    test('LFM2 的 <|think|> 变体', () {
      final parts = splitThinking('<|think|>推理内容<|/think|>答案');
      expect(parts.thinking, '推理内容');
      expect(parts.answer, '答案');
    });

    test('大小写不敏感', () {
      final parts = splitThinking('<THINK>思考</Think>回答');
      expect(parts.thinking, '思考');
      expect(parts.answer, '回答');
    });

    test('标签前有正文时保留前置文本', () {
      final parts = splitThinking('前置说明<think>思考</think>正文');
      expect(parts.answer, '前置说明正文');
      expect(parts.thinking, '思考');
    });

    test('空字符串安全', () {
      final parts = splitThinking('');
      expect(parts.state, ThinkingState.none);
      expect(parts.answer, isEmpty);
    });

    test('流式过程中的孤立结束标签立即生效', () {
      // 模拟流式：思考内容累积后出现 </think>，此时应立即折叠。
      final parts = splitThinking('思考第一句。思考第二句。</think>');
      expect(parts.thinking, '思考第一句。思考第二句。');
      expect(parts.answer, isEmpty);
      expect(parts.state, ThinkingState.done);
    });
  });

  group('cachedSplitThinking', () {
    test('重复调用返回等价结果', () {
      const raw = '推理</think>答案';
      final a = cachedSplitThinking(raw);
      final b = cachedSplitThinking(raw);
      expect(b.thinking, a.thinking);
      expect(b.answer, a.answer);
      expect(b.state, a.state);
    });

    test('缓存不会污染新内容', () {
      expect(cachedSplitThinking('A</think>B').answer, 'B');
      expect(cachedSplitThinking('C</think>D').answer, 'D');
      expect(cachedSplitThinking('A</think>B').answer, 'B');
    });
  });

  group('真实日志样本（debug_bundle.log）', () {
    test('孤立 </think>：模型只输出结束标签', () {
      const raw = 'Hello! How can I assist you today?\n</think>\n\n你好！有什么可以帮您的吗？';
      final parts = splitThinking(raw);
      expect(parts.state, ThinkingState.done);
      expect(parts.thinking.trim(), 'Hello! How can I assist you today?');
      expect(parts.answer, '你好！有什么可以帮您的吗？');
    });

    test('孤立 </think> 中文推理', () {
      const raw = '用户用中文打招呼，我需要保持友好和一致的语言。\n'
          '让我思考一下：\n1. 我是通义实验室的模型\n'
          '</think>\n\n你好呀！😊 我是通义的智能助手，有什么我可以帮忙的吗？';
      final parts = splitThinking(raw);
      expect(parts.thinking, contains('保持友好'));
      expect(parts.answer, startsWith('你好呀'));
      expect(parts.answer, isNot(contains('</think>')));
    });

    test('图片描述场景', () {
      const raw = '用户现在需要识别图片中的物体，图片里有个鲸鱼形象。\n'
          '首先，分析图片内容：主体是一个黄色的鲸鱼。\n'
          '</think>\n\n这是深奶品牌的鲸形卡通产品，旁边的文字是“depmilk”。';
      final parts = splitThinking(raw);
      expect(parts.thinking, contains('鲸鱼'));
      expect(parts.answer, '这是深奶品牌的鲸形卡通产品，旁边的文字是“depmilk”。');
    });

    test('正常长文（无标签）绝不折叠', () {
      const raw = '# 标题：《我在异世界当上了“无效”的饲养员》\n\n'
          '**作者：** 你（AI）\n**类型：** 轻松、日常、轻微奇幻\n';
      final parts = splitThinking(raw);
      expect(parts.hasThinking, isFalse);
      expect(parts.answer, raw);
    });

    test('无标签 Thinking Process + Output 分隔', () {
      const raw = 'Thinking Process:\n\n'
          '1.  **Analyze the Request:**\n'
          '    *   User says hello.\n'
          '    *   Need a friendly reply.\n\n'
          'Output:\n你好～我是你的智能助手，有什么可以帮你的吗？';
      final parts = splitThinking(raw);
      expect(parts.state, ThinkingState.done);
      expect(parts.thinking, contains('Analyze the Request'));
      expect(parts.answer, '你好～我是你的智能助手，有什么可以帮你的吗？');
    });

    test('无标签 Thinking and Information Extraction', () {
      const raw = 'Thinking and Information Extraction:\n'
          '1.  **User Question**: 你好\n'
          '2.  **Answer**: 打招呼\n\n'
          'Output:\n你好！我是你的助手。';
      final parts = splitThinking(raw);
      expect(parts.thinking, contains('User Question'));
      expect(parts.answer, '你好！我是你的助手。');
    });

    test('无标签推理被截断（无分隔符）→ 整段折叠', () {
      const raw = 'Thinking Process:\n\n'
          '1.  **Analyze the Request:**\n'
          '    *   The user wants a long story.\n'
          '    *   I should keep writing until the token limit';
      final parts = splitThinking(raw);
      expect(parts.state, ThinkingState.done);
      expect(parts.answer, isEmpty);
      expect(parts.hasThinking, isTrue);
    });

    test('以 Okay, the user 开头的自言自语', () {
      const raw = 'Okay, the user wants a story written in Chinese. I need to make it '
          'engaging and warm.\n\nOutput:\n雨下得很大，林小舟撑着伞走在回家的路上。';
      final parts = splitThinking(raw);
      expect(parts.thinking, contains('Okay, the user'));
      expect(parts.answer, startsWith('雨下得很大'));
    });

    test('正常回答以 Thinking 开头但不匹配思考标题 → 不折叠', () {
      const raw = 'Thinking is important because it helps us make better decisions. '
          'Here are three reasons you should slow down and reflect.';
      final parts = splitThinking(raw);
      expect(parts.hasThinking, isFalse);
      expect(parts.answer, raw);
    });

    test('短回答不会被启发式误判', () {
      final parts = splitThinking('你好！有什么我可以帮助你的吗？');
      expect(parts.hasThinking, isFalse);
    });
  });

  group('EngineSettings 思考强度档位', () {
    test('档位映射：关闭/简洁/标准/深入', () {
      final s = EngineSettings();
      s.setThinkingLevel(0);
      expect(s.enableThinking, isFalse);
      expect(s.thinkingLevel, 0);
      s.setThinkingLevel(1);
      expect(s.enableThinking, isTrue);
      expect(s.thinkingBudget, 512);
      expect(s.thinkingLevel, 1);
      s.setThinkingLevel(2);
      expect(s.thinkingBudget, 2048);
      expect(s.thinkingLevel, 2);
      s.setThinkingLevel(3);
      expect(s.thinkingBudget, 8192);
      expect(s.thinkingLevel, 3);
    });

    test('越界档位被夹取', () {
      final s = EngineSettings();
      s.setThinkingLevel(99);
      expect(s.thinkingLevel, 3);
      s.setThinkingLevel(-5);
      expect(s.thinkingLevel, 0);
    });

    test('关闭或标准档不注入提示词，简洁/深入档注入', () {
      final s = EngineSettings();
      s.setThinkingLevel(0);
      expect(s.systemPromptWithThinking(), s.systemPrompt.trim());
      s.setThinkingLevel(2);
      expect(s.systemPromptWithThinking(), s.systemPrompt.trim());
      s.setThinkingLevel(1);
      expect(s.systemPromptWithThinking(), contains('Keep your reasoning concise'));
      s.setThinkingLevel(3);
      expect(
        s.systemPromptWithThinking(),
        contains('Think thoroughly and step by step'),
      );
    });

    test('档位与 budget 在 JSON 往返后保持一致', () {
      final s = EngineSettings();
      s.setThinkingLevel(3);
      final round = EngineSettings.fromJson(s.toJson());
      expect(round.thinkingLevel, 3);
      expect(round.thinkingBudget, 8192);
    });

    test('推理模型按「思考」标签识别，普通模型不识别', () {
      final reasoning = ModelSpec.fromJson({
        'id': 'x', 'name': 'X', 'vendor': 'v', 'paramsB': 1,
        'sizeBytes': 1, 'contextLength': 4096, 'quant': 'q',
        'description': 'd', 'tags': ['思考', '中英'],
        'modelScopeRepo': 'r', 'hfRepo': 'h', 'accent': '#000000',
        'recommended': false, 'temperature': 0.7, 'topP': 0.9, 'topK': 40,
      });
      final plain = ModelSpec.fromJson({
        'id': 'y', 'name': 'Y', 'vendor': 'v', 'paramsB': 1,
        'sizeBytes': 1, 'contextLength': 4096, 'quant': 'q',
        'description': 'd', 'tags': ['稳定', '中英'],
        'modelScopeRepo': 'r', 'hfRepo': 'h', 'accent': '#000000',
        'recommended': false, 'temperature': 0.7, 'topP': 0.9, 'topK': 40,
      });
      expect(reasoning.isReasoning, isTrue);
      expect(plain.isReasoning, isFalse);
    });
  });
}
