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
  });

  final String id;
  final String name;
  final String vendor;
  final double paramsB;
  final int sizeBytes;
  final int contextLength;
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

  String get paramsLabel {
    if (paramsB < 0.2) return '${(paramsB * 1000).round()}M';
    return '${paramsB.toStringAsFixed(paramsB == paramsB.roundToDouble() ? 1 : 2)}B';
  }

  factory ModelSpec.fromJson(Map<String, dynamic> json) {
    return ModelSpec(
      id: json['id'] as String,
      name: json['name'] as String,
      vendor: json['vendor'] as String,
      paramsB: (json['paramsB'] as num).toDouble(),
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      contextLength: (json['contextLength'] as num).toInt(),
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
    );
  }
}

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    this.stats,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final ChatRole role;
  String content;
  GenerationStats? stats;
  final DateTime createdAt;

  bool get isUser => role == ChatRole.user;

  ChatMessage copyWith({String? content, GenerationStats? stats}) {
    return ChatMessage(
      role: role,
      content: content ?? this.content,
      stats: stats ?? this.stats,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content,
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
  String systemPrompt;

  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'topP': topP,
        'topK': topK,
        'maxNewTokens': maxNewTokens,
        'contextMessages': contextMessages,
        'threads': threads,
        'backend': backend,
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
      systemPrompt: json['systemPrompt'] as String? ??
          'You are a helpful, concise on-device assistant. Reply in the same language as the user.',
    );
  }

  String encodeOverrides(ModelSpec model) {
    return jsonEncode({
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
      'repetition_penalty': 1.0,
      'presence_penalty': 0.0,
      'frequency_penalty': 0.0,
      'max_new_tokens': maxNewTokens,
    });
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
      final raw = map['stats'];
      final stats = raw is String
          ? GenerationStats.fromJson(
              (jsonDecode(raw) as Map).cast<String, dynamic>())
          : raw is Map
              ? GenerationStats.fromJson(raw.cast<String, dynamic>())
              : const GenerationStats();
      return EngineEvent(type, stats: stats);
    }
    return EngineEvent(type, message: map['message'] as String?);
  }
}
