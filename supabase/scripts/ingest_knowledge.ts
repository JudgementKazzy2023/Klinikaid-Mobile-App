import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";

// Load environment variables (Deno style)
const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const geminiApiKey = Deno.env.get("GEMINI_API_KEY");

if (!supabaseUrl || !supabaseServiceKey || !geminiApiKey) {
  console.error("Missing environment variables. Please set SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, and GEMINI_API_KEY.");
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseServiceKey);

interface ClinicDocument {
  title: string;
  content: string;
}

const documents: ClinicDocument[] = [
  {
    title: "Laboratory Operating Hours",
    content: "Bloodcare Medical Laboratory is open for patient testing from Monday to Saturday from 6:00 AM to 5:00 PM, and Sunday from 7:00 AM to 12:00 PM. Closed on major public holidays. Blood draws and specimen drop-offs must occur at least 30 minutes before closing time."
  },
  {
    title: "Clinic Location and Contact Details",
    content: "Bloodcare Medical Laboratory is located in Burgos, Rodriguez, Rizal, Philippines. For inquiries, you can reach us via telephone at (02) 8123-4567, mobile at 0917-123-4567, or email at contact@bloodcarelab.ph."
  },
  {
    title: "Services Offered",
    content: "We offer diagnostic testing including: Complete Blood Count (CBC), Urinalysis, Fecalysis, Lipid Profile, Blood Typing, Fasting Blood Sugar (FBS), Electrocardiogram (ECG), Pelvic Ultrasound, Whole Abdomen Ultrasound, Hepatobiliary Ultrasound, and X-ray services."
  },
  {
    title: "Preparation for Electrocardiogram (ECG)",
    content: "No fasting is required for an ECG. Patients should wear comfortable, loose two-piece clothing (e.g., shirt and pants or skirt) as chest electrodes must be attached. Avoid applying body lotions, oils, or skin creams to the chest, arms, or legs before the procedure."
  },
  {
    title: "Preparation for Whole Abdomen / Upper Abdomen Ultrasound",
    content: "Whole Abdomen or Upper Abdomen Ultrasounds require strict fasting. Patients must not eat or drink anything (including water, coffee, or gum) for 6 to 8 hours prior to their scheduled scan. Fasting helps reduce gas in the bowel for a clearer liver, gallbladder, and pancreas image."
  },
  {
    title: "Preparation for Pelvic / Lower Abdomen Ultrasound",
    content: "Pelvic or Lower Abdomen Ultrasounds do not require fasting, but require a full bladder. Patients must drink 4 to 6 full glasses of water 1 hour before the scan and must NOT urinate (void bladder) until the ultrasound examination is complete."
  },
  {
    title: "Preparation for Fasting Blood Sugar (FBS) & Lipid Profile Tests",
    content: "Fasting Blood Sugar (FBS) and Lipid Profile blood tests require fasting. The patient must have no food or drink (except plain water) for 10 to 12 hours before blood collection. Avoid alcohol and heavy meals the night before testing."
  },
  {
    title: "Document Submission Guidelines",
    content: "Patients must submit a clear, legible photograph of their diagnostic referral slip or laboratory request form. The document must clearly show the patient's full name, the request date, the requesting physician's name, signature, and license number, along with the specific lab tests ordered. Submissions will be marked as pending until approved by receptionist staff."
  },
  {
    title: "Laboratory Test Pricing",
    content: "Our baseline diagnostic test fees are: Complete Blood Count (CBC) is PHP 250. Urinalysis is PHP 150. Fecalysis is PHP 150. Fasting Blood Sugar (FBS) is PHP 200. Electrocardiogram (ECG) is PHP 400. Pelvic Ultrasound is PHP 950. Whole Abdomen Ultrasound is PHP 1,500. Urgently processed requests (Stat) incur a PHP 100 convenience fee."
  }
];

async function getEmbedding(text: string): Promise<number[]> {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent?key=${geminiApiKey}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "models/gemini-embedding-001",
        content: {
          parts: [{ text: text }],
        },
        output_dimensionality: 768,
      }),
    }
  );

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Gemini Embedding API error: ${errorText}`);
  }

  const json = await response.json();
  const embedding = json.embedding?.values;
  if (!embedding || embedding.length !== 768) {
    throw new Error(`Expected a 768-dimensional embedding, got ${embedding?.length}`);
  }
  return embedding;
}

async function run() {
  console.log(`Starting ingestion of ${documents.length} clinic documents...`);
  
  for (const doc of documents) {
    try {
      console.log(`Embedding document: "${doc.title}"...`);
      const embedding = await getEmbedding(doc.content);
      
      const { error } = await supabase.from("rag_documents").insert({
        title: doc.title,
        content: doc.content,
        embedding: embedding,
        metadata: { is_placeholder: true }
      });
      
      if (error) {
        console.error(`Error inserting "${doc.title}": ${error.message}`);
      } else {
        console.log(`Successfully ingested "${doc.title}"`);
      }
    } catch (e) {
      console.error(`Failed to ingest "${doc.title}":`, e);
    }
  }
  
  console.log("Ingestion completed.");
}

run();
