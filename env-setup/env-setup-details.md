
## Environment setup

This section outlines the steps in detail to configure Google Cloud environment that is required in order to run the code samples in this repo. Please refer [README](../README.md) for running provisioning steps using Cloud Build.


![arch](/images/env.png)

- NVIDIA Triton Inference Server is deployed to a dedicated GPU node pool on a GKE cluster
- Anthos Service Mesh is used to manage, observe and secure communication to Triton Inference Server
- All external traffic to Triton is routed through Istio Ingress Gateway, enabling fine-grained traffic management and progressive deployments
- Managed Prometheus is used to monitor the Triton Inference Server pods


To set up the environment execute the following steps.

### Select a Google Cloud project

In the Google Cloud Console, on the project selector page, [select or create a Google Cloud project](https://console.cloud.google.com/projectselector2/home/dashboard?_ga=2.77230869.1295546877.1635788229-285875547.1607983197&_gac=1.82770276.1635972813.Cj0KCQjw5oiMBhDtARIsAJi0qk2ZfY-XhuwG8p2raIfWLnuYahsUElT08GH1-tZa28e230L3XSfYewYaAlEMEALw_wcB). You need to be a project owner in order to set up the environment


### Enable the required services

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



### Provision infrastructure

Provisioning of the infrastructure has been automated with Terraform. The Terraform configuration performs the following tasks:

- Creates a network and a subnet for a GKE cluster
- Creates a zonal GKE cluster with two node pools: a CPU node pool and a GPU node pool
- Enables Workload Identity and creates and configures a service account to be used by NVIDIA Triton Inference Server
- Registers the cluster with the Anthos fleet and configures Anthos Service Mesh
- Enables managed data collection for the cluster to integrate with Managed Service for Prometheus
- Creates a GCS bucket for the NVIDIA Triton Inference Server's model repository 


The Terraform configuration assumes that the Anthos Service Mesh fleet feature has been enabled. 

```bash
gcloud container fleet mesh enable --project $PROJECT_ID

```

Clone the github repo.

```bash
git clone https://github.com/jarokaz/triton-on-gke-sandbox
```


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
- `MACHINE_TYPE` - The machine type for the Triton GPU node pool (default: `n1-standard-4`)
- `ACCELERATOR_TYPE` - Type of accelerator (GPUs) for the Triton node pool (default: `nvidia-tesla-t4`)
- `ACCELERATOR_COUNT` - Number of accelerator(s) (GPUs) for the Triton node pool (default: `1`)

```bash
export PROJECT_ID=jk-mlops-dev
export REGION=us-central1
export ZONE=us-central1-a
export NETWORK_NAME=jk-gke-network
export SUBNET_NAME=jk-gke-subnet
export GCS_BUCKET_NAME=jk-triton-repository
export GKE_CLUSTER_NAME=jk-ft-gke
export TRITON_SA_NAME=triton-sa
export TRITON_NAMESPACE=triton
export MACHINE_TYPE=n1-standard-4
export ACCELERATOR_TYPE=NVIDIA_TESLA_T4
export ACCELERATOR_COUNT=1
```

By default, the Terraform configurations uses Cloud Storage for the Terraform state. Set the following environment variables to the GCS location for the state.


```bash
TF_STATE_BUCKET=jk-mlops-dev-tf-state
TF_STATE_PREFIX=jax-to-ft-demo 
```

Create Cloud Storage bucket to save Terraform State
```bash
gcloud storage buckets create gs://$TF_STATE_BUCKET --location=$REGION
```

Start provisioning.

```bash
cd ~/triton-on-gke-sandbox/env-setup/terraform
```

```bash
terraform init \
-backend-config="bucket=$TF_STATE_BUCKET" \
-backend-config="prefix=$TF_STATE_PREFIX" 

terraform apply \
-var=project_id=$PROJECT_ID \
-var=region=$REGION \
-var=zone=$ZONE \
-var=network_name=$NETWORK_NAME \
-var=subnet_name=$SUBNET_NAME \
-var=repository_bucket_name=$GCS_BUCKET_NAME \
-var=cluster_name=$GKE_CLUSTER_NAME \
-var=triton_sa_name=$TRITON_SA_NAME \
-var=triton_namespace=$TRITON_NAMESPACE \
-var=machine_type=$MACHINE_TYPE \
-var=accelerator_type=$ACCELERATOR_TYPE \
-var=accelerator_count=$ACCELERATOR_COUNT

```

### Finalize the setup

To finalize the setup you follow the below steps to:
- Install and configure Istio Ingress Gatewy, 
- Install GPU drivers, and
- Deploy NVIDIA Triton Inference Server


Start by configuring access to the cluster.


```bash
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} --project ${PROJECT_ID} --zone ${ZONE} 
```

```bash
kubectl create clusterrolebinding cluster-admin-binding --clusterrole cluster-admin --user "$(gcloud config get-value account)"
```

#### Deploy Ingress Gateway

##### Enable automatic sidecar injection


To enable auto-injection, you label your namespaces with the default injection labels if the default tag is set up, or with the revision label to your namespace.

Use the following command to locate the available release channels:

```bash
kubectl -n istio-system get controlplanerevision
```

The output is similar to the following:

```bash
NAME                AGE
asm-managed         6d7h

```

In the output, select the value under the NAME column is the REVISION label that corresponds to the available release channel for the Anthos Service Mesh version. Apply this label to your namespaces, and remove the istio-injection label (if it exists). In the following command, replace REVISION with the revision label you noted above, and replace NAMESPACE with the name of the namespace where you want to enable auto-injection:

```bash
REVISION=$(kubectl -n istio-system get controlplanerevision -o=jsonpath='{.items..metadata.name}')

kubectl label namespace $TRITON_NAMESPACE  istio-injection- istio.io/rev=$REVISION --overwrite
```


You can ignore the message "istio-injection not found" in the output. That means that the namespace didn't previously have the istio-injection label, which you should expect in new installations of Anthos Service Mesh or new deployments. Because auto-injection fails if a namespace has both the istio-injection and the revision label, all kubectl label commands in the Anthos Service Mesh documentation include removing the istio-injection label.

##### Install the gateway

You can deploy the gateway using the example gateway configuration in the `env-setup/istio-ingressgateway` directory as is, or modify it as needed.

```bash
cd ~/triton-on-gke-sandbox/env-setup

kubectl apply -n $TRITON_NAMESPACE -f istio-ingressgateway
```

Verify that the new services are working correctly.

```bash
kubectl get pod,service -n $TRITON_NAMESPACE

```

The output should be similar to the following:

```bash
NAME                                      READY   STATUS    RESTARTS   AGE
pod/istio-ingressgateway-856b7c77-bdb77   1/1     Running   0          3s

NAME                           TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)        AGE
service/istio-ingressgateway   LoadBalancer   10.24.5.129    34.82.157.6      80:31904/TCP   3s
```

#### Deploy NVIDIA GPU drivers

You need to install NVIDIA's device drivers on the GPU nodes. Google provides a DaemonSet that you can apply to install the drivers.

To deploy the installation DaemonSet and install the default GPU driver version, run the following command:

```bash
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded-latest.yaml 
```


#### Deploy Triton Inference Server

##### Copy sample models to the repository

NVIDIA Triton Inference Server will not start if the are no models in the model repository. Copy a sample model from the `/env-setup/model_repository` to the GCS bucket provisioned by Terraform.

```
gsutil cp -r ~/triton-on-gke-sandbox/env-setup/model_repository gs://${GCS_BUCKET_NAME} 
```

##### Configure Triton Deployment parameters 

Deployment of NVIDIA Triton Inference Server has been configured with *Kustomize*. 


Before deploying the configuration, update the `configs.env` file with the values appropriate for your environment. The following parameters are required

- `model_repository` - The GCS path to your model repository
- `ksa` - The name of the Triton service account that was provisioned by Terraform


```bash
cd ~/triton-on-gke-sandbox/env-setup/kustomize

cat << EOF > ~/triton-on-gke-sandbox/env-setup/kustomize/configs.env
model_repository=gs://${GCS_BUCKET_NAME}/model_repository
ksa=${TRITON_SA_NAME}
EOF
```

Update the namespace.

```bash
kustomize edit set namespace $TRITON_NAMESPACE
```

If you want to use a different NVIDIA Triton Inference Server container image than the one in the default configuration - `nvcr.io/nvidia/tritonserver:22.01-py3`, update and execute the following command.

```bash
kustomize edit set  image "nvcr.io/nvidia/tritonserver:22.01-py3=<UPDATE-CONTAINER-IMAGE>"
```

##### Deploy the configuration

Validate that the Kustomize configuration does not have any errors.

```bash
kubectl kustomize ./
```

Deploy to the cluster.

```bash
kubectl apply -k ./
```

##### Run healthcheck

To validate that NVIDIA Triton Inference Server has been deployed successfully try to access the server's health check API and invoke a sample model.


You will access the server through Istio Ingress Gateway. Start by getting the external IP address of the  `istio-ingressgateway` service.

```bash
kubectl get services -n $TRITON_NAMESPACE
```

Invoke the health check API.

```bash
ISTIO_GATEWAY_IP_ADDRESS=$(kubectl get services -n $TRITON_NAMESPACE \
   -o=jsonpath='{.items[?(@.metadata.name=="istio-ingressgateway")].status.loadBalancer.ingress[0].ip}')

curl -v ${ISTIO_GATEWAY_IP_ADDRESS}/v2/health/ready
```

If the returned status is `200OK` the server is up and accessible through the gateway.

You can now invoke the sample model. Use the NVIDIA Triton Inference Server SDK container image.


```bash
docker run -it --rm --net=host  \
-e ISTIO_GATEWAY_IP_ADDRESS=${ISTIO_GATEWAY_IP_ADDRESS} \
nvcr.io/nvidia/tritonserver:22.01-py3-sdk
```

After the container starts execute the following command from the containers command line:

```bash
/workspace/install/bin/image_client -u  $ISTIO_GATEWAY_IP_ADDRESS -m densenet_onnx -c 3 -s INCEPTION /workspace/images/mug.jpg
```

## Clean up


To clean up the environment use Terraform.


```bash
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