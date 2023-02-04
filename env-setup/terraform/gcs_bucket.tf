# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.



resource "google_storage_bucket" "model_repository" {
    name          = var.repository_bucket_name
    location      = var.region
    storage_class = "REGIONAL"
    force_destroy = var.force_destroy
    uniform_bucket_level_access = true 
}


resource "google_storage_bucket_iam_member" "triton_sa_repository_permissions" {
  bucket = google_storage_bucket.model_repository.name
  role = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${module.triton_workload_identity.gcp_service_account_email}"
}