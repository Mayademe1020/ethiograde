import 'dart:io';
import 'dart:convert';

void main(List<String> args) async {
  final prompt = args.isNotEmpty ? args.join(' ') : 'Hello, respond with just OK';

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

  print('Testing Gemini API key: ${apiKey.substring(0, 8)}...');

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

  try {
    final httpClient = HttpClient();
    final request = await httpClient.postUrl(url);
    request.headers.contentType = ContentType.json;
    request.write(requestBody);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();

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

    print('Response: ${text.trim()}');

    if (text.trim().toUpperCase().contains('OK')) {
      print('\n✅ API key works! Quota available.');
    } else {
      print('\n⚠️ Key works but unexpected response.');
    }
  } catch (e) {
    print('Error: $e');
    exit(1);
  }
}
