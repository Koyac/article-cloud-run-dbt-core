data "google_project" "current" {
  project_id = var.project_id
}

locals {
  # Cloud Schedulerのサービスエージェント（Google管理）
  # このエージェントが「指定したサービスアカウントでOAuthトークンを作る」ための権限付与に使います。
  cloudscheduler_service_agent = "service-${data.google_project.current.number}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"
}

# 必要なAPIを有効化します（環境によっては組織ポリシーで手動有効化が必要です）
resource "google_project_service" "run" {
  count   = var.enable_apis ? 1 : 0
  project = var.project_id
  service = "run.googleapis.com"
}

resource "google_project_service" "cloudscheduler" {
  count   = var.enable_apis ? 1 : 0
  project = var.project_id
  service = "cloudscheduler.googleapis.com"
}

# （任意）Secret Manager を使う場合のみ有効化します
resource "google_project_service" "secretmanager" {
  count   = (var.enable_apis && var.create_profiles_secret) ? 1 : 0
  project = var.project_id
  service = "secretmanager.googleapis.com"
}

# dbt Core を実行する Cloud Run Job に付与する実行用サービスアカウント
# このSAがBigQueryに対してクエリ実行・読み取り等を行います。
resource "google_service_account" "dbt_runtime" {
  project      = var.project_id
  account_id   = "dbt-runtime"
  display_name = "dbt runtime (Cloud Run Job)"
}

# dbt実行SAにBigQuery権限を付与
# NOTE: ここでは説明のためプロジェクト権限を付けていますが、本番は dataset 単位で絞るのがおすすめです。
resource "google_project_iam_member" "dbt_runtime_bigquery" {
  for_each = toset(var.bigquery_project_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.dbt_runtime.email}"
}

# （任意）dbtの profiles.yml などを入れる Secret の“入れ物”だけ作成します。
# 値（Secret Version）は Terraform 管理しない前提（tfstateに平文を残さないため）。
resource "google_secret_manager_secret" "dbt_profiles" {
  count = var.create_profiles_secret ? 1 : 0
  depends_on = [
    google_project_service.secretmanager,
  ]

  project   = var.project_id
  secret_id = var.profiles_secret_id

  replication {
    auto {}
  }
}

# dbt実行SAにSecret参照権限を付与（Secretを使う場合のみ）
resource "google_secret_manager_secret_iam_member" "dbt_runtime_can_read_profiles" {
  count     = var.create_profiles_secret ? 1 : 0
  project   = var.project_id
  secret_id = google_secret_manager_secret.dbt_profiles[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.dbt_runtime.email}"
}

# Cloud Run Job（= dbt Coreを動かす実行単位）
# コンテナイメージ（dbt入り）を指定し、argsで `dbt build` 等を実行します。
resource "google_cloud_run_v2_job" "dbt" {
  depends_on = [
    google_project_service.run,
  ]

  name     = var.job_name
  project  = var.project_id
  location = var.region

  template {
    template {
      service_account = google_service_account.dbt_runtime.email
      timeout         = "${var.timeout_seconds}s"
      max_retries     = var.max_retries

      containers {
        image   = var.container_image
        command = length(var.container_command) == 0 ? null : var.container_command
        args    = var.container_args
      }
    }
  }
}

# Cloud Scheduler が Cloud Run Job を起動するために使う呼び出し用サービスアカウント
# “dbt実行用SA”と分けることで、
# - Schedulerは「Jobを起動できるだけ」
# - Jobの実行権限（BigQuery等）は実行用SAに閉じ込める
# という責務分離ができます。
resource "google_service_account" "scheduler_invoker" {
  project      = var.project_id
  account_id   = "dbt-scheduler-invoker"
  display_name = "Cloud Scheduler -> Cloud Run Jobs invoker"
}

# Cloud Scheduler が scheduler_invoker SA を使って OAuth トークンを発行できるようにする
# Cloud Schedulerのサービスエージェントに対して
# scheduler_invoker SA の token 作成権限（TokenCreator）を付与します。
resource "google_service_account_iam_member" "allow_cloudscheduler_token_creator" {
  service_account_id = google_service_account.scheduler_invoker.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${local.cloudscheduler_service_agent}"
}

# scheduler_invoker SA に Job 起動権限を付与
# Cloud Scheduler はこのSAで署名したリクエストを送るため、
# scheduler_invoker SA に Cloud Run Job の起動権限（run.invoker）を付与します。
resource "google_cloud_run_v2_job_iam_member" "scheduler_can_run_job" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.dbt.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_invoker.email}"
}

# 定期実行のトリガ（Cloud Scheduler）
# Cloud Run Jobs API の `:run` エンドポイントに HTTP POST することで Job を起動します。
resource "google_cloud_scheduler_job" "run_dbt" {
  depends_on = [
    google_project_service.cloudscheduler,
    google_cloud_run_v2_job.dbt,
    google_service_account_iam_member.allow_cloudscheduler_token_creator,
    google_cloud_run_v2_job_iam_member.scheduler_can_run_job,
  ]

  project   = var.project_id
  region    = var.region
  name      = "${var.job_name}-schedule"
  schedule  = var.schedule
  time_zone = var.time_zone

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${google_cloud_run_v2_job.dbt.name}:run"

    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode("{}")

    oauth_token {
      service_account_email = google_service_account.scheduler_invoker.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}
