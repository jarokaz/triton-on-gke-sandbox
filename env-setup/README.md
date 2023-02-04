# Setting up the environment




```
export PROJECT_ID=jk-mlops-dev
export REGION=us-central1
export ZONE=us-central1-a
export NETWORK_NAME=jk-gke-network
export SUBNET_NAME=jk-gke-subnet
export GCS_BUCKET_NAME=jk-triton-repository
export GKE_CLUSTER_NAME=jk-ft-gke

```

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

```
terraform destroy \
--target google_storage_bucket.model_repository \
-var=project_id=$PROJECT_ID \
-var=region=$REGION \
-var=zone=$ZONE \
-var=network_name=$NETWORK_NAME \
-var=subnet_name=$SUBNET_NAME \
-var=repository_bucket_name=$GCS_BUCKET_NAME \
-var=cluster_name=$GKE_CLUSTER_NAME


```


### Configure access to the cluster

```
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} --project ${PROJECT_ID} --zone ${ZONE} 
```

Make sure you can run kubectl locally to access the cluster

```
kubectl create clusterrolebinding cluster-admin-binding --clusterrole cluster-admin --user "$(gcloud config get-value account)"
```

### Deploy NVIDIA drivers

```
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded-latest.yaml 
```


#### Test driver installation

```
kubectl apply -f nvidia-smi.yaml

kubectl get pods

kubectl logs <POD>

kubectl delete -f nvidia-smi.yaml
```


### Deploy Triton Inference Server

#### Clone Triton repo

```
git clone https://github.com/triton-inference-server/server.git
cd server/deploy/gcp
```


#### Create a bucket for model repository

```
gsutil mb gs://jk-triton-repository

```

#### Copy sample models to the repository

```
gsutil cp -r docs/examples/model_repository gs://jk-triton-repository/model_repository
```


#### Install Prometheus and Grafana 

```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts

helm install example-metrics --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false prometheus-community/kube-prometheus-stack
```

###### Verify installation

In Cloud Shell

```
kubectl port-forward service/example-metrics-grafana 8080:80

```


#### Install Triton helm chart

Config the chart

cat << EOF > ~/server/deploy/gcp/config.yaml
namespace: default
image:
  imageName: gcr.io/jk-mlops-dev/bignlp-inference:22.08-py3
  modelRepositoryPath: gs://jk-triton-repository/model_repository
serviceAccountName: triton-ksa
EOF


cat << EOF > ~/server/deploy/gcp/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ template "triton-inference-server.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    app: {{ template "triton-inference-server.name" . }}
    chart: {{ template "triton-inference-server.chart" . }}
    release: {{ .Release.Name }}
    heritage: {{ .Release.Service }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ template "triton-inference-server.name" . }}
      release: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ template "triton-inference-server.name" . }}
        release: {{ .Release.Name }}

    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.imageName }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}

          resources:
            limits:
              nvidia.com/gpu: {{ .Values.image.numGpus }}

          args: ["tritonserver", "--model-store={{ .Values.image.modelRepositoryPath }}"]

          ports:
            - containerPort: 8000
              name: http
            - containerPort: 8001
              name: grpc
            - containerPort: 8002
              name: metrics
          livenessProbe:
            httpGet:
              path: /v2/health/live
              port: http
          readinessProbe:
            initialDelaySeconds: 5
            periodSeconds: 5
            httpGet:
              path: /v2/health/ready
              port: http

      serviceAccountName: {{ .Values.serviceAccountName }}
      nodeSelector:
        iam.gke.io/gke-metadata-server-enabled: "true"
      securityContext:
        runAsUser: 1000
        fsGroup: 1000
EOF


Install the chart

```
cd ~/server/deploy/gcp

helm install triton -f config.yaml . 
```

Run healthcheck

```
kubectl port-forward $(kubectl get pod --selector="app=triton-inference-server" \
  --output jsonpath='{.items[0].metadata.name}') 8000:8000
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/v2/health/ready
```

```
curl -s -o /dev/null -w "%{http_code}" http://34.70.95.90:8000/v2/health/ready
```

```
curl -v 35.232.27.33:8000/v2/health/ready
```

```
docker run -it --rm --net=host nvcr.io/nvidia/tritonserver:22.08-py3-sdk
```

```
/workspace/install/bin/image_client -u  35.232.27.33:8000 -m densenet_onnx -c 3 -s INCEPTION /workspace/images/mug.jpg
```

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
