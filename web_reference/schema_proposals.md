# Mobile-Originated Schema Proposals

This file tracks schema modifications and policies introduced during mobile app development that need to be adopted by the web team to maintain canonical backend parity.

---

## 1. Patients Table Insert Policy

* **Date Proposed**: 2026-05-24
* **Origin**: Phase 2 (Auth & Patient Onboarding)
* **Status**: **PENDING WEB-TEAM ADOPTION** (Implemented on mobile project `vxnkpcqyrxdqxpvutkmm` for testing/onboarding)

### SQL Statement
```sql
CREATE POLICY "Patients can insert own patient record"
  ON public.patients FOR INSERT
  WITH CHECK (profile_id = auth.uid());
```

### Rationale
* The mobile patient onboarding flow requires new users (role = `patient`) to insert their clinical registration data directly into `public.patients` (linked via `profile_id` referencing their authenticated user ID).
* The web team's canonical `schema.sql` only granted `ALL` permissions on the `patients` table to admins and receptionists. Consequently, the onboarding insert failed with PostgreSQL error code `42501` (Access Denied / RLS Blocked).
* This policy safely permits authenticated patients to insert *only* their own patient record matching their unique user ID (`auth.uid()`).

---

## 2. Storage RLS Policies for Patient Documents Bucket

* **Date Proposed**: 2026-06-02
* **Origin**: Phase 4 (Edge OCR & Document Submission)
* **Status**: **PENDING WEB-TEAM ADOPTION** (Proposing bucket creation and policy deployment)

### SQL Statement
```sql
-- Bucket Creation
INSERT INTO storage.buckets (id, name, public) 
VALUES ('patient-documents', 'patient-documents', false);

-- Policy 1: Patients can upload to their own folder
CREATE POLICY "patients upload own folder"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'patient-documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Policy 2: Patients can read their own folder
CREATE POLICY "patients select own folder"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'patient-documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Policy 3: Clinic staff can view all patient documents
CREATE POLICY "clinic staff view all documents"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'patient-documents'
    AND (SELECT role FROM public.profiles WHERE id = auth.uid()) IN ('receptionist', 'department_staff', 'medical_specialist', 'admin')
  );
```

### Rationale
* Patients need a secure, isolated storage bucket to upload captured referral and diagnostic records.
* The bucket must be private. Policies 1 and 2 restrict patients' access solely to their own directory prefix (matching their authenticated UUID folder).
* Policy 3 grants clinic staff view permissions over all uploaded patient documents to support reception desk verification and medical analysis flows.

---

## 3. Vector Similarity Matching Function (match_rag_documents)

* **Date Proposed**: 2026-06-02
* **Origin**: Phase 5 (RAG Chatbot via Edge Function)
* **Status**: **PENDING WEB-TEAM ADOPTION** (Proposing RPC function deployment)

### SQL Statement
```sql
CREATE OR REPLACE FUNCTION public.match_rag_documents(
  query_embedding vector(768),
  match_threshold float,
  match_count int
)
RETURNS TABLE (
  id uuid,
  title text,
  content text,
  metadata jsonb,
  similarity float
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    rag.id,
    rag.title,
    rag.content,
    rag.metadata,
    1 - (rag.embedding <=> query_embedding) AS similarity
  FROM public.rag_documents rag
  WHERE 1 - (rag.embedding <=> query_embedding) > match_threshold
  ORDER BY rag.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;
```

### Rationale
* The Deno/TypeScript Edge Function must perform Cosine similarity vector search over the `rag_documents` table to retrieve relevant clinic knowledge chunks.
* This RPC function exposes pgvector's cosine distance operator (`<=>`) securely and allows client-side or server-side functions to execute query matching with thresholds.

---

## Phase 6 Merge Checklist Items
- [x] Verify that the web team has incorporated the `"Patients can insert own patient record"` policy into the canonical schema. (Adopted: 2026-06-15)
- [x] Verify that the web team has created the `'patient-documents'` private storage bucket and deployed the corresponding Storage object policies. (Adopted: 2026-06-15)
- [x] Verify that the web team has deployed the `match_rag_documents` vector search RPC function. (Adopted: 2026-06-16)
- [x] Confirm the policies and functions are deployed in the shared production/staging database environment prior to the final project merge. (Confirmed: 2026-06-16)
