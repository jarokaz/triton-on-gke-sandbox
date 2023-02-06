# Setting up the environment

- Architecture diagram TBD
- Architecture description TBD. 

Preliminary design patterns:

- A GKE cluster is configured in a VPC-Native mode and is configured to use Workload Identity
- Triton components are deployed to a dedicated namespace and run on a dedicated GPU node pool
- Anthos Service Mesh is used to manage Triton access
- Istio Ingress Gateway is configured using a [dedicated application gateway pattern](https://istio.io/v1.15/docs/setup/additional-setup/gateway/#dedicated-application-gateway)
- Istion Ingress Gateway pods run on a default node pool
- Anthos fleet is in the same project as the GKE cluster
- Managed Prometheus is used to monitor the Triton deployment



## Enable the required services

From [Cloud Shell](https://cloud.google.com/shell/docs/using-cloud-shelld.google.com/shell/docs/using-cloud-shell), run the following commands to enable the required Cloud APIs:

```bash
export PROJECT_ID=<YOUR_PROJECT_ID>
 
gcloud config set project $PROJECT_ID
 
gcloud services enable \
  cloudbuild.googleapis.com \
  compute.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  container.googleapis.com \
  cloudapis.googleapis.com \
  cloudtrace.googleapis.com \
  containerregistry.googleapis.com \
  iamcredentials.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  storage.googleapis.com \
  mesh.googleapis.com
```

## Enable the Anthos Service Mesh fleet feature

The Terraform configuration that provisions a GKE cluster and auxiliary components assumes that the Anthos Service Mesh fleet feature has been enabled. 

```
gcloud container fleet mesh enable --project $PROJECT_ID
```

## Clone the repo

```
git clone https://github.com/jarokaz/triton-on-gke-sandbox

```

## Provision infrastructure

Use Terraform to provision the infrastructure described in the overview section.

Update the environment variables to reflect your environment resource names.

```
export PROJECT_ID=jk-mlops-dev
export REGION=us-central1
export ZONE=us-central1-a
export NETWORK_NAME=jk-gke-network
export SUBNET_NAME=jk-gke-subnet
export GCS_BUCKET_NAME=jk-triton-repository
export GKE_CLUSTER_NAME=jk-ft-gke
export TRITON_SA_NAME=triton-sa
export TRITON_NAMESPACE=triton

```

Set your GCS backend for Terraform state

```
STATE_BUCKET=jk-mlops-dev-tf-state
STATE_PREFIX=jax-to-ft-demo 
```

Run terraform

```
cd ~/triton-on-gke-sandbox/env-setup/terraform
```

```
terraform init \
-backend-config="bucket=$STATE_BUCKET" \
-backend-config="prefix=$STATE_PREFIX" 

terraform apply \
-var=project_id=$PROJECT_ID \
-var=region=$REGION \
-var=zone=$ZONE \
-var=network_name=$NETWORK_NAME \
-var=subnet_name=$SUBNET_NAME \
-var=repository_bucket_name=$GCS_BUCKET_NAME \
-var=cluster_name=$GKE_CLUSTER_NAME \
-var=triton_sa_name=$TRITON_SA_NAME \
-var=triton_namespace=$TRITON_NAMESPACE

```

## Configure access to the cluster

```
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} --project ${PROJECT_ID} --zone ${ZONE} 
```

```
kubectl create clusterrolebinding cluster-admin-binding --clusterrole cluster-admin --user "$(gcloud config get-value account)"
```

## Deploy Ingress Gateway

### Enable automatic sidecar injection


Use the following command to locate the available release channels:

```
kubectl -n istio-system get controlplanerevision
```

he output is similar to the following:

```
NAME                AGE
asm-managed         6d7h

```

In the output, select the value under the NAME column is the REVISION label that corresponds to the available release channel for the Anthos Service Mesh version. Apply this label to your namespaces, and remove the istio-injection label (if it exists). In the following command, replace REVISION with the revision label you noted above, and replace NAMESPACE with the name of the namespace where you want to enable auto-injection:

```
REVISION=asm-managed

kubectl label namespace $TRITON_NAMESPACE  istio-injection- istio.io/rev=$REVISION --overwrite
```


You can ignore the message "istio-injection not found" in the output. That means that the namespace didn't previously have the istio-injection label, which you should expect in new installations of Anthos Service Mesh or new deployments. Because auto-injection fails if a namespace has both the istio-injection and the revision label, all kubectl label commands in the Anthos Service Mesh documentation include removing the istio-injection label.

### Install the gateway

```
cd ~/triton-on-gke-sandbox/env-setup

kubectl apply -n $TRITON_NAMESPACE -f istio-ingressgateway
```

verify that the new services are working correctly.

```
kubectl get pod,service -n $TRITON_NAMESPACE

```

Verify the output is similar to the following:

```
NAME                                      READY   STATUS    RESTARTS   AGE
pod/istio-ingressgateway-856b7c77-bdb77   1/1     Running   0          3s

NAME                           TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)        AGE
service/istio-ingressgateway   LoadBalancer   10.24.5.129    34.82.157.6      80:31904/TCP   3s
```

## Deploy NVIDIA drivers

```
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded-latest.yaml 
```


## Enable Managed Prometheous

```
gcloud container clusters update $GKE_CLUSTER_NAME --enable-managed-prometheus --zone $ZONE
```




## Deploy Triton Inference Server

### Copy sample models to the repository

```
gsutil cp -r model_repository gs://${GCS_BUCKET_NAME} 
```


### Configure Triton Deployment parameters 

```
cd ~/triton-on-gke-sandbox/env-setup/kustomize
```

Update the `configs.env` file with the values appropriate for your deployment. The following parameters are required

- `model_repository` - The GCS path to Triton model repository
- `ksa` - The name of Triton service account that was provisioned during the setup

```
cat << EOF > ~/triton-on-gke-sandbox/env-setup/kustomize/configs.env
model_repository=gs://${GCS_BUCKET_NAME}/model_repository
ksa=${TRITON_SA_NAME}
EOF
```


```

kustomize edit set  image "nvcr.io/nvidia/tritonserver:23.01-py3=gcr.io/jk-mlops-dev/bignlp-inference:22.08-py3"

kustomize edit set namespace $TRITON_NAMESPACE

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
kubectl get services -n $TRITON_NAMESPACE
```


```
TRITON_IP_ADDRESS=34.171.168.240

curl -v ${TRITON_IP_ADDRESS}:8000/v2/health/ready
```

#### Test the sample model

```
docker run -it --rm --net=host nvcr.io/nvidia/tritonserver:22.08-py3-sdk
```

```
/workspace/install/bin/image_client -u  34.171.168.240:8000 -m densenet_onnx -c 3 -s INCEPTION /workspace/images/mug.jpg
```

## Clean up


Run Terraform

```
terraform destroy \
-var=project_id=$PROJECT_ID \
-var=region=$REGION \
-var=zone=$ZONE \
-var=network_name=$NETWORK_NAME \
-var=subnet_name=$SUBNET_NAME \
-var=repository_bucket_name=$GCS_BUCKET_NAME \
-var=cluster_name=$GKE_CLUSTER_NAME \
-var=triton_sa_name=$TRITON_SA_NAME \
-var=triton_namespace=$TRITON_NAMESPACE

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




