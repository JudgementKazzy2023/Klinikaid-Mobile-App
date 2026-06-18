import 'dart:convert';
import 'dart:io';

const String supabaseUrl = 'https://onzeyejlfydvvbkejvwf.supabase.co';

class ClinicDocument {
  final String title;
  final String content;

  const ClinicDocument({required this.title, required this.content});
}

const List<ClinicDocument> documents = [
  ClinicDocument(
    title: "Laboratory Operating Hours",
    content: "Bloodcare Medical Laboratory is open for patient testing from Monday to Saturday from 6:00 AM to 5:00 PM, and Sunday from 7:00 AM to 12:00 PM. Closed on major public holidays. Blood draws and specimen drop-offs must occur at least 30 minutes before closing time."
  ),
  ClinicDocument(
    title: "Clinic Location and Contact Details",
    content: "Bloodcare Medical Laboratory is located in Burgos, Rodriguez, Rizal, Philippines. For inquiries, you can reach us via telephone at (02) 8123-4567, mobile at 0917-123-4567, or email at contact@bloodcarelab.ph."
  ),
  ClinicDocument(
    title: "Services Offered",
    content: "We offer diagnostic testing including: Complete Blood Count (CBC), Urinalysis, Fecalysis, Lipid Profile, Blood Typing, Fasting Blood Sugar (FBS), Electrocardiogram (ECG), Pelvic Ultrasound, Whole Abdomen Ultrasound, Hepatobiliary Ultrasound, and X-ray services."
  ),
  ClinicDocument(
    title: "Preparation for Electrocardiogram (ECG)",
    content: "No fasting is required for an ECG. Patients should wear comfortable, loose two-piece clothing (e.g., shirt and pants or skirt) as chest electrodes must be attached. Avoid applying body lotions, oils, or skin creams to the chest, arms, or legs before the procedure."
  ),
  ClinicDocument(
    title: "Preparation for Whole Abdomen / Upper Abdomen Ultrasound",
    content: "Whole Abdomen or Upper Abdomen Ultrasounds require strict fasting. Patients must not eat or drink anything (including water, coffee, or gum) for 6 to 8 hours prior to their scheduled scan. Fasting helps reduce gas in the bowel for a clearer liver, gallbladder, and pancreas image."
  ),
  ClinicDocument(
    title: "Preparation for Pelvic / Lower Abdomen Ultrasound",
    content: "Pelvic or Lower Abdomen Ultrasounds do not require fasting, but require a full bladder. Patients must drink 4 to 6 full glasses of water 1 hour before the scan and must NOT urinate (void bladder) until the ultrasound examination is complete."
  ),
  ClinicDocument(
    title: "Preparation for Fasting Blood Sugar (FBS) & Lipid Profile Tests",
    content: "Fasting Blood Sugar (FBS) and Lipid Profile blood tests require fasting. The patient must have no food or drink (except plain water) for 10 to 12 hours before blood collection. Avoid alcohol and heavy meals the night before testing."
  ),
  ClinicDocument(
    title: "Document Submission Guidelines",
    content: "Patients must submit a clear, legible photograph of their diagnostic referral slip or laboratory request form. The document must clearly show the patient's full name, the request date, the requesting physician's name, signature, and license number, along with the specific lab tests ordered. Submissions will be marked as pending until approved by receptionist staff."
  ),
  ClinicDocument(
    title: "Laboratory Test Pricing",
    content: "Our baseline diagnostic test fees are: Complete Blood Count (CBC) is PHP 250. Urinalysis is PHP 150. Fecalysis is PHP 150. Fasting Blood Sugar (FBS) is PHP 200. Electrocardiogram (ECG) is PHP 400. Pelvic Ultrasound is PHP 950. Whole Abdomen Ultrasound is PHP 1,500. Urgently processed requests (Stat) incur a PHP 100 convenience fee."
  )
];

Future<List<double>> getEmbedding(String text, String geminiApiKey, HttpClient client) async {
  final uri = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent?key=$geminiApiKey'
  );
  
  final request = await client.postUrl(uri);
  request.headers.contentType = ContentType.json;
  
  final body = {
    'model': 'models/gemini-embedding-001',
    'content': {
      'parts': [{'text': text}]
    },
    'output_dimensionality': 768
  };
  
  request.write(json.encode(body));
  final response = await request.close();
  
  if (response.statusCode != 200) {
    final responseBody = await response.transform(utf8.decoder).join();
    throw Exception('Gemini Embedding API error: $responseBody');
  }
  
  final responseBody = await response.transform(utf8.decoder).join();
  final data = json.decode(responseBody) as Map<String, dynamic>;
  final embedding = data['embedding']?['values'] as List<dynamic>?;
  
  if (embedding == null || embedding.length != 768) {
    throw Exception('Expected a 768-dimensional embedding, got ${embedding?.length}');
  }
  
  return embedding.cast<double>();
}

Future<void> insertDocument(
  ClinicDocument doc,
  List<double> embedding,
  String serviceRoleKey,
  HttpClient client,
) async {
  final uri = Uri.parse('$supabaseUrl/rest/v1/rag_documents');
  final request = await client.postUrl(uri);
  
  request.headers.set('apikey', serviceRoleKey);
  request.headers.set('Authorization', 'Bearer $serviceRoleKey');
  request.headers.contentType = ContentType.json;
  request.headers.set('Prefer', 'return=minimal');
  
  final body = {
    'title': doc.title,
    'content': doc.content,
    'embedding': embedding,
    'metadata': {'is_placeholder': true}
  };
  
  request.write(json.encode(body));
  final response = await request.close();
  
  if (response.statusCode >= 300) {
    final responseBody = await response.transform(utf8.decoder).join();
    throw Exception('Supabase REST Insert error: $responseBody');
  }
}

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart bin/ingest_knowledge.dart <SUPABASE_SERVICE_ROLE_KEY>');
    exit(1);
  }
  
  final serviceRoleKey = args[0];
  
  // Try to find GEMINI_API_KEY from supabase/.env
  String? geminiApiKey;
  try {
    final envFile = File('supabase/.env');
    if (await envFile.exists()) {
      final lines = await envFile.readAsLines();
      for (var line in lines) {
        if (line.startsWith('GEMINI_API_KEY=')) {
          geminiApiKey = line.split('=')[1].trim().replaceAll('"', '').replaceAll("'", '');
          break;
        }
      }
    }
  } catch (e) {
    print('Could not read supabase/.env: $e');
  }
  
  if (geminiApiKey == null) {
    print('Error: GEMINI_API_KEY not found in supabase/.env');
    exit(1);
  }
  
  final client = HttpClient();
  
  print('Starting ingestion of ${documents.length} clinic documents...');
  
  for (var doc in documents) {
    try {
      print('Embedding document: "${doc.title}"...');
      final embedding = await getEmbedding(doc.content, geminiApiKey, client);
      
      print('Inserting into Supabase...');
      await insertDocument(doc, embedding, serviceRoleKey, client);
      print('Successfully ingested "${doc.title}"');
    } catch (e) {
      print('Failed to ingest "${doc.title}": $e');
    }
  }
  
  client.close();
  print('Ingestion completed.');
}
