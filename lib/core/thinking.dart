/// 思考内容（reasoning）与正文的分离逻辑。
///
/// 单独成文件的原因：这段解析既要在 UI 每帧调用，又要能被单元测试
/// 直接覆盖。它是纯函数，不依赖 Flutter。
library;

/// 解析后的状态，供 UI 决定折叠块的标题文案。
enum ThinkingState {
  /// 没有任何思考标记，整段都是正文。
  none,

  /// 已检测到思考标记，但正文还没出现（推理仍在进行）。
  thinking,

  /// 思考已结束，正文已开始。
  done,
}

/// 一条消息拆分后的结果。
class ThinkingParts {
  const ThinkingParts({
    this.thinking = '',
    this.answer = '',
    this.state = ThinkingState.none,
  });

  /// 推理过程（已去掉标记本身）。
  final String thinking;

  /// 去掉推理后的正文。
  final String answer;

  final ThinkingState state;

  bool get hasThinking => thinking.trim().isNotEmpty;

  @override
  String toString() =>
      'ThinkingParts(state: $state, thinking: ${thinking.length}, '
      'answer: ${answer.length})';
}

/// 常见的推理标记对（起始, 结束）。
///
/// 不同模型的写法差异很大，且 MNN 的 chat template 常常把起始标记
/// 直接注入到 prompt 里（`...assistant<think>`），模型只负责吐结束标记。
/// 因此两种形态都必须支持：成对出现、以及只有孤立结束标记。
const List<(String, String)> _thinkingTagPairs = [
  ('<think>', '</think>'),
  ('<thinking>', '</thinking>'),
  ('<thought>', '</thought>'),
  ('<reasoning>', '</reasoning>'),
  ('<analysis>', '</analysis>'),
  ('<|think|>', '<|/think|>'),
  ('<|reasoning|>', '<|/reasoning|>'),
  ('【思考】', '【/思考】'),
];

/// 最宽松地拆分 [raw]。
///
/// 判定顺序：
/// 1. 存在起始标记：其后的内容归入思考，直到对应的结束标记；
///    结束标记缺失时（模型被 token 上限截断），剩余全部归入思考。
/// 2. 没有起始标记、但存在孤立的结束标记（prompt 里已注入起始标记的
///    典型情况）：结束标记之前全部是思考。
/// 3. 完全没有标签：尝试识别「Thinking Process:」这类显式思考文本
///    （见 [_splitUnmarkedThinking]），识别不到就当正文。
///
/// 第 3 条刻意保守：只有当文本以明确的思考标题开头时才折叠，宁可漏判
/// 也绝不把正常答案整段藏起来。
ThinkingParts splitThinking(String raw) {
  if (raw.isEmpty) return const ThinkingParts();

  final lower = _asciiLower(raw);

  // 找出最早出现的起始标记。
  var openAt = -1;
  var openLen = 0;
  var closeTag = '';
  for (final pair in _thinkingTagPairs) {
    final at = lower.indexOf(_asciiLower(pair.$1));
    if (at < 0) continue;
    if (openAt < 0 || at < openAt) {
      openAt = at;
      openLen = pair.$1.length;
      closeTag = pair.$2;
    }
  }

  if (openAt >= 0) {
    final bodyStart = openAt + openLen;
    final closeAt =
        closeTag.isEmpty ? -1 : lower.indexOf(_asciiLower(closeTag), bodyStart);
    if (closeAt >= 0) {
      return ThinkingParts(
        thinking: raw.substring(bodyStart, closeAt),
        answer: (raw.substring(0, openAt) +
                raw.substring(closeAt + closeTag.length))
            .trim(),
        state: ThinkingState.done,
      );
    }
    // 起始标记存在但没闭合：剩余内容全部是推理，正文为空。
    return ThinkingParts(
      thinking: raw.substring(bodyStart),
      answer: raw.substring(0, openAt).trim(),
      state: ThinkingState.thinking,
    );
  }

  // 没有起始标记，检查孤立的结束标记（模板已注入起始标记的情况）。
  var closeAt = -1;
  var closeLen = 0;
  for (final pair in _thinkingTagPairs) {
    final at = lower.indexOf(_asciiLower(pair.$2));
    if (at < 0) continue;
    if (closeAt < 0 || at < closeAt) {
      closeAt = at;
      closeLen = pair.$2.length;
    }
  }
  if (closeAt >= 0) {
    return ThinkingParts(
      thinking: raw.substring(0, closeAt),
      answer: raw.substring(closeAt + closeLen).trim(),
      state: ThinkingState.done,
    );
  }

  // 完全没有标签：部分模型的 chat template 会把标签整个吞掉，只留下
  // 以 "Thinking Process:" / "Okay, the user wants..." 开头的纯文本推理。
  final unmarked = _splitUnmarkedThinking(raw);
  if (unmarked != null) return unmarked;

  return ThinkingParts(answer: raw);
}

/// 无标签推理的启发式识别。
///
/// 需要的条件非常严格，两条同时成立才折叠：
/// 1. 文本开头（前 64 字符）是明确的思考标题；
/// 2. 或者能在正文中找到明确的答案分隔符（`Output:` / `Final Answer:` …）。
///
/// 只满足第 1 条的，把整段都当思考（用户仍可展开查看）；这样即使模型
/// 没有给出分隔符（推理被截断），也不会把大段英文分析糊在正文里。
ThinkingParts? _splitUnmarkedThinking(String raw) {
  final lead = raw.trimLeft();
  if (lead.length < 24) return null;

  final head = _asciiLower(lead.length > 64 ? lead.substring(0, 64) : lead);
  final isThinkingHead = _thinkingHeadPatterns.any(head.startsWith);
  if (!isThinkingHead) return null;

  // 找一个行首的答案分隔符，优先取最靠后、最明确的那种。
  var splitAt = -1;
  var sepLen = 0;
  for (final sep in _answerSeparators) {
    final at = _asciiLower(lead).lastIndexOf(sep);
    if (at <= 0) continue;
    if (at > splitAt) {
      splitAt = at;
      sepLen = sep.length;
    }
  }

  if (splitAt >= 0) {
    final answer = lead.substring(splitAt + sepLen).trim();
    // 分隔符后面必须有实质内容，否则视为「只有思考」。
    if (answer.isNotEmpty) {
      return ThinkingParts(
        thinking: lead.substring(0, splitAt).trim(),
        answer: answer,
        state: ThinkingState.done,
      );
    }
  }

  return ThinkingParts(
    thinking: lead,
    answer: '',
    state: ThinkingState.done,
  );
}

/// 显式思考标题（小写比较，需出现在文本开头）。
const List<String> _thinkingHeadPatterns = [
  'thinking process',
  'thinking and information',
  'thought process',
  'reasoning process',
  'my thinking',
  'thinking:',
  'analysis:',
  'reasoning:',
  'okay, the user',
  'the user wants',
  'the user is asking',
  'let me think',
  '思考过程',
  '分析过程',
  '推理过程',
  '我的思考',
  '让我想想',
  '让我思考',
];

/// 行首的答案分隔符（包含前导换行，避免匹配正文里的普通词）。
const List<String> _answerSeparators = [
  '\noutput:',
  '\nfinal answer:',
  '\nanswer:',
  '\nresponse:',
  '\n答案：',
  '\n最终答案：',
  '\n回答：',
  '\n输出：',
];

/// 供 UI 使用的带缓存版本。
///
/// 流式生成时每个 token 都会触发 rebuild，若每帧都对整段文本做 8 次
/// `indexOf` 扫描，长回复下会明显浪费 CPU。这里做一个极小的 MRU 缓存，
/// 命中的是「内容未变的历史消息」，只有正在流式的那条会真正重算。
ThinkingParts cachedSplitThinking(String raw) {
  final cached = _cache.remove(raw);
  if (cached != null) {
    _cache[raw] = cached; // 命中后移到队尾（最近使用）
    return cached;
  }
  final parts = splitThinking(raw);
  if (_cache.length >= _cacheCapacity) {
    _cache.remove(_cache.keys.first);
  }
  _cache[raw] = parts;
  return parts;
}

const int _cacheCapacity = 12;
final Map<String, ThinkingParts> _cache = <String, ThinkingParts>{};

/// 仅对 ASCII 字母做小写转换。
///
/// 不能用 `toLowerCase()`：个别语言（如土耳其语）会把一个字符映射成
/// 两个码元，导致 `indexOf` 得到的位置与原文 `substring` 错位。显式
/// 只处理 A-Z 可以保证长度恒定——这些标签本身也全是 ASCII。
String _asciiLower(String input) {
  var changed = false;
  final units = input.codeUnits;
  final out = List<int>.from(units);
  for (var i = 0; i < units.length; i++) {
    final c = units[i];
    if (c >= 0x41 && c <= 0x5A) {
      out[i] = c + 0x20;
      changed = true;
    }
  }
  return changed ? String.fromCharCodes(out) : input;
}
