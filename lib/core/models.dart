import 'dart:convert';

enum ChatRole { system, user, assistant }

class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.name,
    required this.vendor,
    required this.paramsB,
    required this.sizeBytes,
    required this.contextLength,
    this.contextSource = 'exact',
    required this.quant,
    required this.description,
    required this.tags,
    required this.modelScopeRepo,
    required this.hfRepo,
    required this.accentHex,
    required this.recommended,
    required this.temperature,
    required this.topP,
    required this.topK,
    this.vision = false,
  });

  final String id;
  final String name;
  final String vendor;
  final double paramsB;
  final int sizeBytes;
  final int contextLength;
  /// 上下文长度的来源：`exact` 表示取自模型原生配置
  /// （llm_config.json / 上游 base_model 的 config.json）；
  /// `approx` 表示按模型家族推断，展示时加「≈」前缀以示区别。
  final String contextSource;
  final String quant;
  final String description;
  final List<String> tags;
  final String modelScopeRepo;
  final String hfRepo;
  final String accentHex;
  final bool recommended;
  final double temperature;
  final double topP;
  final int topK;
  /// 是否支持图片输入（MNN Omni 引擎的视觉编码器）。
  final bool vision;

  /// 是否具备原生思考/推理能力（模型库以「思考」标签标记）。
  /// 仅对这类模型展示推理强度控制。
  bool get isReasoning => tags.contains('思考');

  String get paramsLabel {
    if (paramsB < 0.2) return '${(paramsB * 1000).round()}M';
    return '${paramsB.toStringAsFixed(paramsB == paramsB.roundToDouble() ? 1 : 2)}B';
  }

  /// 原生上下文长度的展示文案。
  ///
  /// 数值来自模型自身的 `max_position_embeddings`；按家族推断的加 `≈`
  /// 前缀，避免把估算值当成精确规格展示。
  String get contextLabel {
    if (contextLength <= 0) return '自适应 ctx';
    final text = contextLength >= 1024
        ? '${(contextLength / 1024).round()}K'
        : '$contextLength';
    return contextSource == 'approx' ? '≈$text ctx' : '$text ctx';
  }

  factory ModelSpec.fromJson(Map<String, dynamic> json) {
    return ModelSpec(
      id: json['id'] as String,
      name: json['name'] as String,
      vendor: json['vendor'] as String,
      paramsB: (json['paramsB'] as num).toDouble(),
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      contextLength: (json['contextLength'] as num).toInt(),
      contextSource: json['contextSource'] as String? ?? 'exact',
      quant: json['quant'] as String,
      description: json['description'] as String,
      tags: (json['tags'] as List<dynamic>).cast<String>(),
      modelScopeRepo: json['modelScopeRepo'] as String,
      hfRepo: json['hfRepo'] as String,
      accentHex: json['accent'] as String,
      recommended: json['recommended'] as bool? ?? false,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      topP: (json['topP'] as num?)?.toDouble() ?? 0.9,
      topK: (json['topK'] as num?)?.toInt() ?? 40,
      vision: json['vision'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'vendor': vendor,
        'paramsB': paramsB,
        'sizeBytes': sizeBytes,
        'contextLength': contextLength,
        'quant': quant,
        'description': description,
        'tags': tags,
        'modelScopeRepo': modelScopeRepo,
        'hfRepo': hfRepo,
        'accent': accentHex,
        'recommended': recommended,
        'temperature': temperature,
        'topP': topP,
        'topK': topK,
        if (vision) 'vision': true,
      };
}

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    this.stats,
    this.imagePath,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final ChatRole role;
  String content;
  GenerationStats? stats;

  /// 用户消息附带的本地图片绝对路径。
  final String? imagePath;
  final DateTime createdAt;

  bool get isUser => role == ChatRole.user;

  /// 发给引擎的 content：视觉模型靠 `<img>路径</img>` 标签触发图像编码。
  String get engineContent {
    final path = imagePath;
    if (path == null) return content;
    final tag = '<img>$path</img>';
    return content.isEmpty ? tag : '$content\n$tag';
  }

  ChatMessage copyWith({String? content, GenerationStats? stats}) {
    return ChatMessage(
      role: role,
      content: content ?? this.content,
      stats: stats ?? this.stats,
      imagePath: imagePath,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content,
        if (imagePath != null) 'image': imagePath,
        'createdAt': createdAt.millisecondsSinceEpoch,
        if (stats != null) 'stats': stats!.toJson(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: ChatRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => ChatRole.assistant,
      ),
      content: json['content'] as String? ?? '',
      imagePath: json['image'] as String?,
      stats: json['stats'] == null
          ? null
          : GenerationStats.fromJson(
              (json['stats'] as Map).cast<String, dynamic>()),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class GenerationStats {
  const GenerationStats({
    this.prefillTps = 0,
    this.decodeTps = 0,
    this.promptTokens = 0,
    this.outputTokens = 0,
    this.elapsedMs = 0,
  });

  final double prefillTps;
  final double decodeTps;
  final int promptTokens;
  final int outputTokens;
  final int elapsedMs;

  Map<String, dynamic> toJson() => {
        'prefillTps': prefillTps,
        'decodeTps': decodeTps,
        'promptTokens': promptTokens,
        'outputTokens': outputTokens,
        'elapsedMs': elapsedMs,
      };

  factory GenerationStats.fromJson(Map<String, dynamic> json) {
    return GenerationStats(
      prefillTps: (json['prefillTps'] as num?)?.toDouble() ?? 0,
      decodeTps: (json['decodeTps'] as num?)?.toDouble() ?? 0,
      promptTokens: (json['promptTokens'] as num?)?.toInt() ?? 0,
      outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
      elapsedMs: (json['elapsedMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatSession {
  ChatSession({
    required this.id,
    required this.title,
    required this.modelId,
    required this.modelName,
    required this.messages,
    required this.updatedAt,
  });

  final String id;
  String title;
  final String modelId;
  final String modelName;
  final List<ChatMessage> messages;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'modelId': modelId,
        'modelName': modelName,
        'messages': messages.map((m) => m.toJson()).toList(),
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String,
      title: json['title'] as String? ?? '新对话',
      modelId: json['modelId'] as String? ?? '',
      modelName: json['modelName'] as String? ?? '',
      messages: (json['messages'] as List<dynamic>? ?? const [])
          .map((e) => ChatMessage.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['updatedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class EngineSettings {
  EngineSettings({
    this.temperature = 0.8,
    this.topP = 0.9,
    this.topK = 40,
    this.maxNewTokens = 512,
    this.contextMessages = 24,
    this.threads = 4,
    this.backend = 'cpu',
    this.useMmap = true,
    this.repetitionPenalty = 1.05,
    this.ngramFactor = 1.1,
    this.enableThinking = true,
    this.thinkingBudget = 2048,
    this.systemPrompt =
        'You are a helpful, concise on-device assistant. Reply in the same language as the user.',
  });

  double temperature;
  double topP;
  int topK;
  int maxNewTokens;
  int contextMessages;
  int threads;
  String backend;
  /// 是否用 mmap 方式加载权重（降低内存峰值）。可在设置里关闭以兼容部分机型。
  bool useMmap;
  /// 重复惩罚：>1 时对已出现的 token 降权，抑制小模型陷入重复循环。
  /// MNN 的 sampler 仅在 repetition_penalty>1 或 ngram_factor>1 时才启用惩罚。
  double repetitionPenalty;
  /// n-gram 惩罚因子：>1 时对连续重复的 n 元组降权，专门防「一长串相同字符」。
  double ngramFactor;
  /// 深度思考模型是否输出 `<think>` 思考过程（原生开关）。
  ///
  /// 通过 MNN 的 `jinja.context.enable_thinking` 下发，与官方 iOS App 的
  /// `setThinkingModeEnabled` 完全一致。MNN 引擎没有原生的「思考强度/预算」
  /// 参数，因此详略档位由 [thinkingBudget] 通过系统提示词注入来补充实现。
  bool enableThinking;
  /// 思考详略预算（token 数），驱动「关闭/简洁/标准/深入」四档强度提示词。
  /// 0 表示关闭；>0 时由原生 enable_thinking 开关 + 系统提示词注入共同生效。
  int thinkingBudget;
  String systemPrompt;

  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'topP': topP,
        'topK': topK,
        'maxNewTokens': maxNewTokens,
        'contextMessages': contextMessages,
        'threads': threads,
        'backend': backend,
        'useMmap': useMmap,
        'repetitionPenalty': repetitionPenalty,
        'ngramFactor': ngramFactor,
        'enableThinking': enableThinking,
        'thinkingBudget': thinkingBudget,
        'systemPrompt': systemPrompt,
      };

  factory EngineSettings.fromJson(Map<String, dynamic> json) {
    return EngineSettings(
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.8,
      topP: (json['topP'] as num?)?.toDouble() ?? 0.9,
      topK: (json['topK'] as num?)?.toInt() ?? 40,
      maxNewTokens: (json['maxNewTokens'] as num?)?.toInt() ?? 512,
      contextMessages: (json['contextMessages'] as num?)?.toInt() ?? 24,
      threads: (json['threads'] as num?)?.toInt() ?? 4,
      backend: json['backend'] as String? ?? 'cpu',
      useMmap: json['useMmap'] as bool? ?? true,
      repetitionPenalty:
          (json['repetitionPenalty'] as num?)?.toDouble() ?? 1.05,
      ngramFactor: (json['ngramFactor'] as num?)?.toDouble() ?? 1.1,
      enableThinking: json['enableThinking'] as bool? ?? true,
      thinkingBudget: (json['thinkingBudget'] as num?)?.toInt() ?? 2048,
      systemPrompt: json['systemPrompt'] as String? ??
          'You are a helpful, concise on-device assistant. Reply in the same language as the user.',
    );
  }

  /// 思考强度档位数：关闭 / 简洁 / 标准 / 深入。
  static const int thinkingLevelCount = 4;
  static const List<String> thinkingLevelLabels = ['关闭', '简洁', '标准', '深入'];
  static const List<String> thinkingLevelSubtitles = [
    '直接回答，不输出推理过程',
    '简要思考',
    '平衡思考与速度',
    '充分展开推理过程',
  ];

  /// 当前思考强度档位（0..3）。
  int get thinkingLevel {
    if (!enableThinking) return 0;
    if (thinkingBudget <= 0) return 2;
    if (thinkingBudget <= 1024) return 1;
    if (thinkingBudget >= 4096) return 3;
    return 2;
  }

  /// 设置思考强度档位，联动原生开关与提示词预算。
  void setThinkingLevel(int level) {
    final clamped = level.clamp(0, thinkingLevelCount - 1);
    enableThinking = clamped > 0;
    thinkingBudget = switch (clamped) {
      0 => 0,
      1 => 512,
      2 => 2048,
      3 => 8192,
      _ => 2048,
    };
  }

  /// 将思考详略约束注入系统提示词，作为原生开关的补充。
  /// 仅当思考开启且强度非「标准」时注入，避免改变默认行为。
  String systemPromptWithThinking() {
    final base = systemPrompt.trim();
    if (!enableThinking || thinkingBudget <= 0) return base;
    final hint = thinkingBudget <= 1024
        ? 'Keep your reasoning concise and brief.'
        : thinkingBudget >= 4096
            ? 'Think thoroughly and step by step before answering.'
            : '';
    if (hint.isEmpty) return base;
    return base.isEmpty ? hint : '$base\n$hint';
  }

  /// 生成 MNN 可识别的思考开关配置片段。
  ///
  /// MNN（含官方 MnnLlmChat / llm_demo）只认 `jinja.context.enable_thinking`
  /// 这个布尔开关，并不存在 `thinking_budget` 字段：此前把
  /// `enable_thinking` / `thinking_budget` 写在 overrides 顶层，引擎完全忽略，
  /// 这正是"思考开关和强度始终无效"的根因。
  ///
  /// 返回的片段可直接用于 load 的 overrides，也可传给 `set_config` 实时生效。
  /// [enable] 为 null 时表示不改变当前值（仅用于构造空片段，实际调用总会传值）。
  Map<String, dynamic> thinkingConfigOverrides({bool? enable}) {
    return {
      'jinja': {
        'context': {
          'enable_thinking': enable ?? enableThinking,
        },
      },
    };
  }

  /// [useMmapOverride] 用于加载失败时临时回退到非 mmap 重试，不改写持久化设置。
  String encodeOverrides(
    ModelSpec model, {
    String? mmapDir,
    bool? useMmapOverride,
  }) {
    final overrides = <String, dynamic>{
      'backend_type': backend,
      'thread_num': threads,
      'precision': 'low',
      'memory': 'low',
      'sampler_type': 'mixed',
      'temperature': temperature,
      'top_k': topK,
      'top_p': topP,
      'min_p': 0.05,
      'tfs_z': 1.0,
      'typical': 0.95,
      // 反退化：MNN 的 sampler 仅在下列值越过阈值时才真正施加惩罚。
      // 此前全部是 no-op（1.0/0/0/无 ngram），小模型（qwen3.5-0.8b、
      // minicpm4 等）长生成时容易陷入重复循环，反复吐出同一 token（如「H」）。
      'repetition_penalty': repetitionPenalty,
      'frequency_penalty': 0.1,
      'presence_penalty': 0.0,
      'n_gram': 8,
      'ngram_factor': ngramFactor,
      'max_new_tokens': maxNewTokens,
    };
    // 深度思考模型（Qwen3 等）的开关必须放在 jinja.context 里才会被 MNN
    // 的 chat template 识别——顶层 enable_thinking 会被静默忽略。此处在
    // load 时先写入一次think 开关，运行中改动由 AppStore.applyThinking 通过
    // set_config 实时下发（见 thinkingConfigOverrides）。
    overrides['jinja'] = thinkingConfigOverrides()['jinja'];
    // 大模型优先用 mmap 加载权重，避免整块读入内存导致 OOM 闪退。
    // tmp_path 指向应用私有可写目录，MNN 用于放置 mmap 临时文件。
    final mmap = useMmapOverride ?? useMmap;
    if (mmap && mmapDir != null && mmapDir.isNotEmpty) {
      overrides['use_mmap'] = true;
      overrides['tmp_path'] = mmapDir;
    }
    return jsonEncode(overrides);
  }
}

class DownloadProgress {
  const DownloadProgress({
    required this.received,
    required this.total,
    this.file,
    this.bytesPerSecond = 0,
  });

  final int received;
  final int total;
  final String? file;
  final double bytesPerSecond;

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0.0, 1.0);
}

class EngineEvent {
  const EngineEvent(this.type, {this.text, this.stats, this.message});

  final String type;
  final String? text;
  final GenerationStats? stats;
  final String? message;

  factory EngineEvent.fromMap(Map<dynamic, dynamic> map) {
    final type = map['type'] as String? ?? 'error';
    if (type == 'token') {
      return EngineEvent(type, text: map['text'] as String? ?? '');
    }
    if (type == 'done') {
      // 原生侧回传的 statsJson 可能因异常变成非法 JSON；解析失败时回退到
      // 空统计，绝不让它冒泡到事件流、否则 generating 将无法复位。
      GenerationStats stats;
      try {
        final raw = map['stats'];
        stats = raw is String
            ? GenerationStats.fromJson(
                (jsonDecode(raw) as Map).cast<String, dynamic>())
            : raw is Map
                ? GenerationStats.fromJson(raw.cast<String, dynamic>())
                : const GenerationStats();
      } catch (_) {
        stats = const GenerationStats();
      }
      return EngineEvent(type, stats: stats);
    }
    return EngineEvent(type, message: map['message'] as String?);
  }
}
