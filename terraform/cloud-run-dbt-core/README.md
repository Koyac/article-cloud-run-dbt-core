# Terraform：dbt Core on Cloud Run Jobs（+ Cloud Scheduler）

このディレクトリは、BigQuery向けの dbt Core を **Cloud Run Jobs** で実行し、**Cloud Scheduler** で定期起動するための Terraform 雛形です。

## 何が作られる？

- dbt 実行用 Service Account
- Cloud Run Job（コンテナ実行）
- Cloud Scheduler Job（Cloud Run Jobs API の `:run` を叩いて起動）
- 最小限の IAM（例：BigQuery Job 実行、Cloud Run Job 起動）

## なぜサービスアカウントを2つに分ける？（権限設計の意図）

この雛形では、サービスアカウントを **実行用** と **起動用** で分離しています。

- **dbt実行用SA（dbt-runtime）**：BigQueryに対する実行権限を持つ（= データへアクセスできる）
- **起動用SA（dbt-scheduler-invoker）**：Cloud Scheduler が Cloud Run Job を **起動するだけ**

こうすることで、

- Scheduler側が万一漏洩しても「Jobを起動できる」止まり
- データアクセス権限は Job 実行環境のSAに閉じ込められる

という形で、最小権限に寄せやすくなります。

## 前提

- Terraform >= 1.5
- Google provider（本コードは `hashicorp/google` を利用）
- dbt Core を実行するコンテナイメージが用意されていること（`var.container_image`）

## はじめ方（ローカルからTerraform実行）

### 0) 認証（gcloud）

TerraformのGoogle providerは、環境により複数の認証方法を取れます。
手元で試すだけなら、まずは gcloud のユーザ認証が簡単です。

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

※ 組織の方針でユーザ認証がNGの場合は、Terraform実行用のサービスアカウントを用意してください。

### 1) 初期化

```bash
cd terraform/cloud-run-dbt-core
terraform init
```

### 2) 実行計画（plan）

```bash
terraform plan \
  -var project_id=YOUR_PROJECT_ID \
  -var region=asia-northeast1 \
  -var container_image=asia-northeast1-docker.pkg.dev/YOUR_PROJECT_ID/REPO/dbt:latest
```

### 3) 適用（apply）

```bash
terraform apply \
  -var project_id=YOUR_PROJECT_ID \
  -var region=asia-northeast1 \
  -var container_image=asia-northeast1-docker.pkg.dev/YOUR_PROJECT_ID/REPO/dbt:latest
```

### 4) 破棄（destroy）

検証後に消す場合：

```bash
terraform destroy \
  -var project_id=YOUR_PROJECT_ID \
  -var region=asia-northeast1 \
  -var container_image=asia-northeast1-docker.pkg.dev/YOUR_PROJECT_ID/REPO/dbt:latest
```

## dbtの認証（推奨：キー不要 / 実行環境のService AccountでADC）

Cloud Run では実行環境に Service Account を付与でき、GCPの **Application Default Credentials (ADC)** が利用できます。

dbt-bigquery の `profiles.yml` 例（概念例）：

```yaml
your_profile:
  target: prod
  outputs:
    prod:
      type: bigquery
      method: oauth
      project: YOUR_PROJECT_ID
      dataset: YOUR_DATASET
      threads: 4
```

`method` の扱いは dbt-bigquery のバージョンや運用方針で変わり得ます。組織要件によっては service-account key を Secret Manager で配布する方式も検討してください（※その場合、鍵管理・ローテーションが必要です）。

## 使い方

```bash
cd terraform/cloud-run-dbt-core
terraform init
terraform plan \
  -var project_id=YOUR_PROJECT_ID \
  -var region=asia-northeast1 \
  -var container_image=asia-northeast1-docker.pkg.dev/YOUR_PROJECT_ID/REPO/dbt:latest

terraform apply
```

作成後、手動で即時実行したい場合（例）：

```bash
gcloud run jobs execute $(terraform output -raw cloud_run_job_name) \
  --region $(terraform output -raw region) \
  --project $(terraform output -raw project_id)
```

## カスタマイズ箇所

- `var.container_command` / `var.container_args`：`dbt build` や `dbt run` など
- `var.schedule`：Cron（例：`0 2 * * *`）
- `var.bigquery_project_roles`：BigQuery権限（本番は dataset 単位のIAMを推奨）

## （任意）Secret Managerで profiles.yml を管理したい場合

Terraformで **Secretの“入れ物だけ”**作り、値（secret version）は運用で投入する方針が安全です（tfstateに平文が残らないため）。

- `create_profiles_secret = true`
- `profiles_secret_id = "dbt-profiles-yml"`（任意）

例：

```bash
terraform apply \
  -var create_profiles_secret=true

# 値の投入（例）
gcloud secrets versions add dbt-profiles-yml \
  --data-file=profiles.yml \
  --project YOUR_PROJECT_ID
```

※ この雛形では Cloud Run Job 側でsecretをマウントしていません。
マウントする場合は `google_cloud_run_v2_job` の `containers { env { ... } volume_mounts { ... } }` を追加してください。

## セキュリティ注意

- 本雛形は「最小構成で動かす」ことを優先した叩き台です。
- 本番では **dataset単位の権限**、VPC接続（必要なら）、監査ログ、アラート、SLO等を必ず設計してください。
