// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:convert';
import 'package:image/image.dart' as img;

const _maxImageBytes = 300 * 1024;
const _maxDimension = 1600;
const _minQuality = 70;

const _prompt = '''You are an exam answer extractor for Ethiopian teachers.
Look at this image of a student's exam paper.
Extract the answer for each question number.
Common Ethiopian format: the answer letter appears
BEFORE the question number like:
B 1. What is the capital?
A 2. What is 2+2?
Rules:
- Extract single letter answers (A-E)
- Ignore student name and non-answer text
- If unclear, skip it
Return ONLY a JSON array.
Format: [{"q":1,"answer":"B","confidence":"high"},...]''';

Future<void> main(List<String> args) async {
  final useGemini = Platform.environment['USE_GEMINI'] == '1';

  if (args.isEmpty) {
    print('Usage:');
    print('  dart scripts/gemini_test.dart <image_path>           (image OCR test)');
    print('  dart scripts/gemini_test.dart "text prompt"          (text-only test)');
    print('  USE_GEMINI=1 dart scripts/gemini_test.dart <path>   (force Gemini)');
    exit(1);
  }

  // Load API keys from .env
  final envFile = File('.env');
  if (!await envFile.exists()) {
    print('Error: .env file not found');
    exit(1);
  }

  final envContent = await envFile.readAsString();
  final envLines = envContent.split('\n').map((l) => l.trim()).toList();

  final String? geminiKey = envLines
      .where((l) => l.startsWith('GEMINI_API_KEY='))
      .map((l) => l.substring('GEMINI_API_KEY='.length))
      .firstOrNull;

  final String? githubToken = envLines
      .where((l) => l.startsWith('GITHUB_TOKEN='))
      .map((l) => l.substring('GITHUB_TOKEN='.length))
      .firstOrNull;

  // Decide provider: GitHub Models primary, Gemini fallback
  final bool useGitHub = !useGemini && githubToken != null && githubToken.isNotEmpty;
  final bool useGeminiProvider = useGemini || (!useGitHub && geminiKey != null && geminiKey.isNotEmpty);

  if (!useGitHub && !useGeminiProvider) {
    print('Error: No API key found in .env (need GITHUB_TOKEN or GEMINI_API_KEY)');
    exit(1);
  }

  final provider = useGitHub ? 'GitHub Models (GPT-4o)' : 'Gemini (gemini-2.0-flash)';
  print('Provider: $provider');

  // Check if argument is an image file or text prompt
  final inputPath = args.first;
  final imageFile = File(inputPath);
  final isImage = await imageFile.exists() &&
      (inputPath.toLowerCase().endsWith('.jpg') ||
       inputPath.toLowerCase().endsWith('.jpeg') ||
       inputPath.toLowerCase().endsWith('.png'));

  String responseBody;
  if (isImage) {
    // Image mode: compress and send with vision prompt
    print('Image mode: $inputPath');
    print('Compressing image...');
    final compressedBytes = await _compressImage(inputPath);
    final sizeKB = compressedBytes.length ~/ 1024;
    print('Compressed to ${sizeKB}KB');
    final base64Image = base64Encode(compressedBytes);

    print('Sending to $provider...\n');
    responseBody = useGitHub
        ? await _sendGitHubModels(base64Image, githubToken)
        : await _sendGemini(base64Image, geminiKey!);
  } else {
    // Text mode: send text prompt directly
    print('Text mode: $inputPath');
    print('Sending to $provider...\n');
    responseBody = useGitHub
        ? await _sendGitHubText(inputPath, githubToken)
        : await _sendGeminiText(inputPath, geminiKey!);
  }

  // Print raw response
  print('=== Raw Response ===');
  print(responseBody);
  print('');

  // Parse response
  final json = jsonDecode(responseBody);

  if (json['error'] != null) {
    print('API Error: ${json['error']['message'] ?? json['error']}');
    exit(1);
  }

  // Extract text from response (different format per provider)
  String? text;
  if (useGitHub) {
    text = json['choices']?[0]?['message']?['content'];
  } else {
    text = json['candidates']?[0]?['content']?['parts']?[0]?['text'];
  }

  if (text == null) {
    print('No text in response');
    exit(1);
  }

  print('=== Model Output ===');
  print(text);
  print('');

  if (!isImage) {
    print('✅ Text test passed!');
    return;
  }

  // Parse extracted answers (image mode only)
  final jsonMatch = RegExp(r'\[.*\]', dotAll: true).firstMatch(text);
  if (jsonMatch == null) {
    print('No JSON array found in response');
    exit(1);
  }

  final answers = jsonDecode(jsonMatch.group(0)!) as List;

  print('=== Extracted Answers ===');
  if (answers.isEmpty) {
    print('No answers detected');
  } else {
    for (final a in answers) {
      final q = a['q'] ?? '?';
      final answer = a['answer'] ?? '?';
      final confidence = a['confidence'] ?? '?';
      print('  Q$q: $answer (confidence: $confidence)');
    }
    print('\nTotal: ${answers.length} answers extracted');
  }
}

Future<String> _sendGitHubModels(String base64Image, String token) async {
  final url = Uri.parse('https://models.github.ai/inference/chat/completions');

  final requestBody = jsonEncode({
    'model': 'gpt-4o',
    'messages': [
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': _prompt},
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:image/jpeg;base64,$base64Image',
            },
          },
        ],
      },
    ],
    'max_tokens': 1024,
    'temperature': 0.1,
  });

  final httpClient = HttpClient();
  final request = await httpClient.postUrl(url);
  request.headers.contentType = ContentType.json;
  request.headers.set('Authorization', 'Bearer $token');
  request.write(requestBody);
  final response = await request.close();
  return response.transform(utf8.decoder).join();
}

Future<String> _sendGemini(String base64Image, String apiKey) async {
  final url = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey',
  );

  final requestBody = jsonEncode({
    'contents': [
      {
        'parts': [
          {'text': _prompt},
          {
            'inline_data': {
              'mime_type': 'image/jpeg',
              'data': base64Image,
            },
          },
        ],
      },
    ],
  });

  final httpClient = HttpClient();
  final request = await httpClient.postUrl(url);
  request.headers.contentType = ContentType.json;
  request.write(requestBody);
  final response = await request.close();
  return response.transform(utf8.decoder).join();
}

Future<String> _sendGitHubText(String prompt, String token) async {
  final url = Uri.parse('https://models.github.ai/inference/chat/completions');

  final requestBody = jsonEncode({
    'model': 'gpt-4o',
    'messages': [
      {'role': 'user', 'content': prompt},
    ],
    'max_tokens': 256,
  });

  final httpClient = HttpClient();
  final request = await httpClient.postUrl(url);
  request.headers.contentType = ContentType.json;
  request.headers.set('Authorization', 'Bearer $token');
  request.write(requestBody);
  final response = await request.close();
  return response.transform(utf8.decoder).join();
}

Future<String> _sendGeminiText(String prompt, String apiKey) async {
  final url = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey',
  );

  final requestBody = jsonEncode({
    'contents': [
      {
        'parts': [
          {'text': prompt},
        ],
      },
    ],
  });

  final httpClient = HttpClient();
  final request = await httpClient.postUrl(url);
  request.headers.contentType = ContentType.json;
  request.write(requestBody);
  final response = await request.close();
  return response.transform(utf8.decoder).join();
}

Future<List<int>> _compressImage(String imagePath) async {
  final bytes = await File(imagePath).readAsBytes();
  img.Image? image = img.decodeImage(bytes);
  if (image == null) throw Exception('Failed to decode image');

  image = img.bakeOrientation(image);

  if (image.width > _maxDimension || image.height > _maxDimension) {
    final longer = image.width > image.height ? image.width : image.height;
    final ratio = _maxDimension / longer;
    image = img.copyResize(
      image,
      width: (image.width * ratio).round(),
      height: (image.height * ratio).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  for (int quality = 90; quality >= _minQuality; quality -= 10) {
    final encoded = img.encodeJpg(image, quality: quality);
    if (encoded.lengthInBytes <= _maxImageBytes) return encoded;
  }

  final resolutions = [1200, 800, 600];
  for (final maxDim in resolutions) {
    if (image.width <= maxDim && image.height <= maxDim) continue;
    final longer = image.width > image.height ? image.width : image.height;
    final ratio = maxDim / longer;
    final resized = img.copyResize(
      image,
      width: (image.width * ratio).round(),
      height: (image.height * ratio).round(),
      interpolation: img.Interpolation.cubic,
    );
    final encoded = img.encodeJpg(resized, quality: _minQuality);
    if (encoded.lengthInBytes <= _maxImageBytes) return encoded;
  }

  final fallback = img.copyResize(image, width: 600, height: (600 * image.height / image.width).round());
  return img.encodeJpg(fallback, quality: _minQuality);
}
