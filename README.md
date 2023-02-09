
# Serving Large Language Models with NVIDIA FasterTransformer and Triton Inference Server

TBD


## Environment setup

This section outlines the steps to configure Google Cloud environment that is required in order to run the code samples in this repo


![arch](/images/env.png)

- NVIDIA Triton Inference Server is deployed to a dedicated GPU node pool on a GKE cluster
- Anthos Service Mesh is used to manage, observe and secure communication to Triton Inference Server
- All external traffic to Triton is routed through Istio Ingress Gateway, enabling fine-grained traffic management and progressive deployments
- Managed Prometheus is used to monitor the Triton Inference Server pods


To set up the environment execute the following steps.

### Select a Google Cloud project

In the Google Cloud Console, on the project selector page, [select or create a Google Cloud project](https://console.cloud.google.com/projectselector2/home/dashboard?_ga=2.77230869.1295546877.1635788229-285875547.1607983197&_gac=1.82770276.1635972813.Cj0KCQjw5oiMBhDtARIsAJi0qk2ZfY-XhuwG8p2raIfWLnuYahsUElT08GH1-tZa28e230L3XSfYewYaAlEMEALw_wcB). You need to be a project owner in order to set up the environment

### Enable the required services

- Clone the GitHub repo.

```bash
git clone https://github.com/jarokaz/triton-on-gke-sandbox
```

- Granting permissions to your Cloud Build service account

```bash
export PROJECT_ID=<YOUR_PROJECT_ID>
 gcloud config set project $PROJECT_ID
```

- Retrieve the email for your project's Cloud Build service account:
```bash
CLOUDBUILD_SA="$(gcloud projects describe $PROJECT_ID \
    --format 'value(projectNumber)')@cloudbuild.gserviceaccount.com"
```

- Grant the required access to your Cloud Build service account:
```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member serviceAccount:$CLOUDBUILD_SA --role roles/owner
```

## Provision infrastructure

The Terraform configuration supports a number of configurable inputs. Refer to the `/env-setup/variables.tf` for the full list and the default settings. You need to set a small set of the required parameters. Set the below environment variables to reflect your environment.

- `PROJECT_ID` - your project ID
- `REGION` - the region for a GKE cluster network
- `ZONE` - the zone for your GKE cluster
- `NETWORK_NAME` - the name for the network
- `SUBNET_NAME` - the name for the subnet
- `GCS_BUCKET_NAME` - the name of the model repository GCS bucket
- `GKE_CLUSTER_NAME` - the name of your cluster
- `TRITON_SA_NAME` - the name for the service account that will be used as the Triton's workload identity
- `TRITON_NAMESAPCE` - the name of a namespace where the solution's components are deployed


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

export DOCKER_ARTIFACT_REPO="llms-on-gke"
export JAX_TO_FT_IMAGE_NAME="jax-to-fastertransformer"
export JAX_TO_FT_IMAGE_URI="gcr.io/"${PROJECT_ID}"/"${DOCKER_ARTIFACT_REPO}"/"${JAX_TO_FT_IMAGE_NAME}
```

By default, the Terraform configurations uses Cloud Storage for the Terraform state. Set the following environment variables to the GCS location for the state.

```bash
export TF_STATE_BUCKET=jk-mlops-dev-tf-state
export TF_STATE_PREFIX=jax-to-ft-demo 
```

Create Cloud Storage bucket to save Terraform State
```bash
gcloud storage buckets create gs://$TF_STATE_BUCKET --location=$REGION
```

Start provisioning by using Cloud Build job to run Terraform and provision resources, deploy Triton Inference server and finalize the setup.

```bash
gcloud builds submit \
  --region $REGION \
  --config cloudbuild.provision.yaml \
  --substitutions _TF_STATE_BUCKET=$TF_STATE_BUCKET,_TF_STATE_PREFIX=$TF_STATE_PREFIX,_REGION=$REGION,_ZONE=$ZONE,_NETWORK_NAME=$NETWORK_NAME,_SUBNET_NAME=$SUBNET_NAME,_GCS_BUCKET_NAME=$GCS_BUCKET_NAME,_GKE_CLUSTER_NAME=$GKE_CLUSTER_NAME,_TRITON_SA_NAME=$TRITON_SA_NAME,_TRITON_NAMESPACE=$TRITON_NAMESPACE,_DOCKERNAME=$JAX_TO_FT_IMAGE_NAME,_JAX_TO_FT_IMAGE_URI=$JAX_TO_FT_IMAGE_URI,_FT_CONVERTER_PATH=$FT_CONVERTER_PATH \
  --timeout "2h" \
  --machine-type=e2-highcpu-32 \
  --quiet
```

### Invoking sample model on Triton

You can now invoke the sample model. Use the NVIDIA Triton Inference Server SDK container image.

Start by configuring access to the cluster.


```
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} --project ${PROJECT_ID} --zone ${ZONE} 
```

```
kubectl create clusterrolebinding cluster-admin-binding --clusterrole cluster-admin --user "$(gcloud config get-value account)"
```


```
docker run -it --rm --net=host  \
-e ISTIO_GATEWAY_IP_ADDRESS=${ISTIO_GATEWAY_IP_ADDRESS} \
nvcr.io/nvidia/tritonserver:22.08-py3-sdk
```

After the container starts execute the following command from the containers command line:

```
/workspace/install/bin/image_client -u  $ISTIO_GATEWAY_IP_ADDRESS -m densenet_onnx -c 3 -s INCEPTION /workspace/images/mug.jpg
```

## Clean up


To clean up the environment use Terraform with Cloud Build.


```bash
gcloud builds submit \
  --region $REGION \
  --config cloudbuild.destroy.yaml \
  --substitutions _TF_STATE_BUCKET=$TF_STATE_BUCKET,_TF_STATE_PREFIX=$TF_STATE_PREFIX,_REGION=$REGION,_ZONE=$ZONE,_NETWORK_NAME=$NETWORK_NAME,_SUBNET_NAME=$SUBNET_NAME,_GCS_BUCKET_NAME=$GCS_BUCKET_NAME,_GKE_CLUSTER_NAME=$GKE_CLUSTER_NAME,_TRITON_SA_NAME=$TRITON_SA_NAME,_TRITON_NAMESPACE=$TRITON_NAMESPACE \
  --timeout "2h" \
  --machine-type=e2-highcpu-32 \
  --quiet
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

docker tag nvcr.io/ea-bignlp/bignlp-inference:22.08-py3 gcr.io/$PROJECT_ID/bignlp-inference:22.08-py3

docker push gcr.io/$PROJECT_ID/bignlp-inference:22.08-py3
```




