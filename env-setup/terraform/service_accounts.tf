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



resource "google_service_account" "triton_sa" {
    project      = data.google_project.project.project_id
    account_id   = var.triton_sa_name
    display_name = "Triton service account"
}

resource "google_project_iam_member" "triton_sa_role_bindings" {
    project  = data.google_project.project.project_id
    for_each = toset(var.triton_sa_roles)
    member   = "serviceAccount:${google_service_account.triton_sa.email}"
    role     = "roles/${each.value}"
}

resource "google_service_account_iam_binding" "triton_workload_identity_binding" {
    service_account_id = google_service_account.triton_sa.name
    role               = "roles/iam.workloadIdentityUser"

    members = [
        "serviceAccount:${data.google_project.project.project_id}.svc.id.goog[${var.triton_ksa_namespace}/${var.triton_ksa_name}]"
    ]
}
