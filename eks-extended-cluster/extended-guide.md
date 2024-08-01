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

5. Check if the sample apps are running (or completed)

```bash
kubectl get pods,svc
kubectl logs cuda-vectoradd
kubectl logs tf-notebook
kubectl port-foward 
```