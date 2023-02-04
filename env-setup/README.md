# Setting up the environment


## Create infrastructure

Update the environment variables to reflect your environment

```
export PROJECT_ID=jk-mlops-dev
export REGION=us-central1
export ZONE=us-central1-a
export NETWORK_NAME=jk-gke-network
export SUBNET_NAME=jk-gke-subnet
export GCS_BUCKET_NAME=jk-triton-repository
export GKE_CLUSTER_NAME=jk-ft-gke

```

Run terraform

```
terraform init
terraform apply \
-var=project_id=$PROJECT_ID \
-var=region=$REGION \
-var=zone=$ZONE \
-var=network_name=$NETWORK_NAME \
-var=subnet_name=$SUBNET_NAME \
-var=repository_bucket_name=$GCS_BUCKET_NAME \
-var=cluster_name=$GKE_CLUSTER_NAME 

```

## Deploy NVIDIA drivers

### Configure access to the cluster

```
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} --project ${PROJECT_ID} --zone ${ZONE} 
```

Make sure you can run kubectl locally to access the cluster

```
kubectl create clusterrolebinding cluster-admin-binding --clusterrole cluster-admin --user "$(gcloud config get-value account)"
```

### Deploy NVIDIA drivers installer demaenset

```
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded-latest.yaml 
```


## Deploy Triton Inference Server

### Enable Managed Prometheous

```
gcloud container clusters update $GKE_CLUSTER_NAME --enable-managed-prometheus --zone $ZONE
```

### Copy sample models to the repository

TBD

`gs://jk-triton-repository-archive` is public. The new NVIDIA Triton github repo seems to be missing example model files.

gsutil cp -r gs://jk-triton-repository-archive/model_repository gs://${GCS_BUCKET_NAME} 

### Set kustomize parameters

```
cd ~/triton-on-gke-sandbox/env-setup/kustomize
```

```
cat << EOF > ~/triton-on-gke-sandbox/env-setup/kustomize/configs.env
model_repository=gs://jk-triton-repository/model_repository
ksa=triton-ksa
```

### Deploy components

Validate configurations

```
kubectl kustomize ./
```

Deploy

```
kubectl apply -k ./

```

#### Run healthcheck

Get external IP address of Triton service

```
kubectl get services
```


```
TRITON_IP_ADDRESS=<YOUR IP ADDRESS>

curl -v ${TRITON_IP_ADDRESS}:8000/v2/health/ready
```

#### Test the sample model

```
docker run -it --rm --net=host nvcr.io/nvidia/tritonserver:22.08-py3-sdk
```

```
/workspace/install/bin/image_client -u  <YOUR IP ADDRESS>:8000 -m densenet_onnx -c 3 -s INCEPTION /workspace/images/mug.jpg
```

## Clean up

Set the environment variables

```
export PROJECT_ID=jk-mlops-dev
export REGION=us-central1
export ZONE=us-central1-a
export NETWORK_NAME=jk-gke-network
export SUBNET_NAME=jk-gke-subnet
export GCS_BUCKET_NAME=jk-triton-repository
export GKE_CLUSTER_NAME=jk-ft-gke

```
Run Terraform

```
terraform destroy \
-var=project_id=$PROJECT_ID \
-var=region=$REGION \
-var=zone=$ZONE \
-var=network_name=$NETWORK_NAME \
-var=subnet_name=$SUBNET_NAME \
-var=repository_bucket_name=$GCS_BUCKET_NAME \
-var=cluster_name=$GKE_CLUSTER_NAME 

```

# TO BE REMOVED


## Accessing NVIDIA bignlp-container

#### Sign in to NGC

https://ngc.nvidia.com/signin

- Organization is ea-participants

#### Authorize docker to access NGC Private Registry

- Get API key
https://ngc.nvidia.com/setup/api-key 

- Authorize docker

```

docker login nvcr.io

Username: $oauthtoken
Password: Your key

```

#### Push the container to Container registry 

```
docker pull nvcr.io/ea-bignlp/bignlp-inference:22.08-py3

docker tag nvcr.io/ea-bignlp/bignlp-inference:22.08-py3 gcr.io/jk-mlops-dev/bignlp-inference:22.08-py3

docker push gcr.io/jk-mlops-dev/bignlp-inference:22.08-py3
```




#### Generate and store service account key for Triton

```
gcloud iam service-accounts keys create gcp-creds.json \
    --iam-account=gke-sa@jk-mlops-dev.iam.gserviceaccount.com
```

```
kubectl create configmap gcpcreds --from-literal "project-id=jk-mlops-dev"
kubectl create secret generic gcpcreds --from-file gcp-creds.json
```

### Recovery

gcloud projects add-iam-policy-binding jk-mlops-dev \
  --member serviceAccount:895222332033@cloudservices.gserviceaccount.com \
  --role roles/editor



  ## Manual setup

export PROJECT_ID=jk-mlops-dev
export ZONE=us-central1-a
export REGION=us-central1
export DEPLOYMENT_NAME=jk-triton-gke-1



gcloud iam service-accounts add-iam-policy-binding triton-sa@jk-mlops-dev.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:jk-mlops-dev.svc.id.goog[default/triton-ksa]"


kubectl annotate serviceaccount triton-ksa \
    --namespace default \
    iam.gke.io/gcp-service-account=triton-sa@jk-mlops-dev.iam.gserviceaccount.com
