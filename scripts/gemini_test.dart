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
  if (args.isEmpty) {
    print('Usage: dart scripts/gemini_test.dart <image_path>');
    exit(1);
  }

  // Load API key
  final envFile = File('.env');
  if (!await envFile.exists()) {
    print('Error: .env file not found');
    exit(1);
  }

  final envContent = await envFile.readAsString();
  final apiKey = envContent
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.startsWith('GEMINI_API_KEY='))
      .map((l) => l.substring('GEMINI_API_KEY='.length))
      .firstOrNull;

  if (apiKey == null || apiKey.isEmpty) {
    print('Error: GEMINI_API_KEY not found in .env');
    exit(1);
  }

  print('API key loaded (${apiKey.substring(0, 8)}...)');

  // Read and compress image
  final imagePath = args.first;
  final imageFile = File(imagePath);
  if (!await imageFile.exists()) {
    print('Error: Image not found: $imagePath');
    exit(1);
  }

  print('Compressing image...');
  final compressedBytes = await _compressImage(imagePath);
  final sizeKB = compressedBytes.length ~/ 1024;
  print('Compressed to ${sizeKB}KB');

  // Base64 encode
  final base64Image = base64Encode(compressedBytes);

  // Send to Gemini
  print('Sending to Gemini...\n');

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
  final responseBody = await response.transform(utf8.decoder).join();

  // Print raw response
  print('=== Raw Response ===');
  print(responseBody);
  print('');

  // Parse response
  final json = jsonDecode(responseBody);

  if (json['error'] != null) {
    print('API Error: ${json['error']['message']}');
    exit(1);
  }

  final text = json['candidates']?[0]?['content']?['parts']?[0]?['text'];
  if (text == null) {
    print('No text in response');
    exit(1);
  }

  print('=== Model Output ===');
  print(text);
  print('');

  // Parse extracted answers
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
