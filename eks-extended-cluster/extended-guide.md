1. Create the EKS cluster on AWS Region

```bash
eksctl create cluster -f cluster-config.yaml --without-nodegroup
```

2. Create the EKS Self-Managed Node Group on AWS Outpost

```bash
eksctl create nodegroup -f cluster-config.yaml
```

3. Deploy the Nvidia GPU Operator

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm upgrade --install --create-namespace -n nvidia-operator nvidia-gpu-operator nvidia/gpu-operator
```

4. Deploy the Nvidia gpu-enabled sample apps

4.1.1. Option 1 - Jupyter Notebook

```bash
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Pod
metadata:
  name: cuda-vectoradd
spec:
  restartPolicy: OnFailure
  containers:
  - name: cuda-vectoradd
    image: "nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda11.7.1-ubuntu20.04"
    resources:
      limits:
        nvidia.com/gpu: 1
---
apiVersion: v1
kind: Service
metadata:
  name: tf-notebook
  labels:
    app: tf-notebook
spec:
  type: NodePort
  ports:
  - port: 80
    name: http
    targetPort: 8888
    nodePort: 30001
  selector:
    app: tf-notebook
---
apiVersion: v1
kind: Pod
metadata:
  name: tf-notebook
  labels:
    app: tf-notebook
spec:
  securityContext:
    fsGroup: 0
  containers:
  - name: tf-notebook
    image: tensorflow/tensorflow:latest-gpu-jupyter
    resources:
      limits:
        nvidia.com/gpu: 1
    ports:
    - containerPort: 8888
      name: notebook
EOF
```

4.1.2. Check if the sample apps are running (or completed)

```bash
kubectl get pods,svc
kubectl logs cuda-vectoradd
kubectl logs tf-notebook
kubectl port-foward 
```

4.2.1.  Option 2 - Open-WebUI with Ollama (requires additional add-ons such as AWS LB Controller and EBS CSI Driver)

```bash
cat <<EOF > open-webui-values.yaml
ollama:
  enabled: true
  fullnameOverride: "open-webui-ollama"
  ollama:
    gpu:
      enabled: true
      type: 'nvidia'
      number: 1
    models:
      - llama3
  runtimeClassName: nvidia
  persistentVolume:
    enabled: true

ingress:
  enabled: true
  class: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/subnets: <replace with the public subnets associated with outpost>
    alb.ingress.kubernetes.io/target-type: ip
EOF

helm repo add open-webui https://helm.openwebui.com/
help repo update
helm upgrade --install open-webui open-webui/open-webui -n open-webui-ollama --create-namespace --values open-webui-values.yaml
```

4.2.2. Check if the sample apps are running (or completed)

```bash
kubectl get ns
kubectl -n open-webui-ollama get pods 
kubectl -n open-webui-ollama get pvc
kubectl -n open-webui-ollama get deployments.apps 
kubectl -n open-webui-ollama get statefulsets.apps 
kubectl -n open-webui-ollama get ingress
kubectl -n open-webui-ollama logs -l app.kubernetes.io/component=open-webui-ollama --tail=-1
```
