1. Create the EKS cluster on AWS Region

```bash
eksctl create cluster -f cluster-config.yaml --without-nodegroup
```

2. Create the EKS Self-Managed Node Group on AWS Outpost

```bash
eksctl create nodegroup -f cluster-config.yaml
```

3. Establish the VPC peering with the default VPC where the bastion is running, and configure the routing tables.

4. Modify EKS Cluster SG to allow connection from Default VPC CIDR on HTTPS

5. Create the ECR Pull-through cache for the Public ECR repositories. Be aware that you need to pull these images using Docker, before these getting available for consumption from EKS Local Cluster (not sure why yet).

```bash
aws ecr create-pull-through-cache-rule \
     --ecr-repository-prefix ecr-public \
     --upstream-registry-url public.ecr.aws \
     --region us-west-2

aws ecr create-pull-through-cache-rule \
     --ecr-repository-prefix k8s \
     --upstream-registry-url registry.k8s.io \
     --region us-west-2
```

3. Install the EKS Add-ons using the Helm Charts (self-managed).

3.1. EBS CSI Driver

3.1.1. Create the EBS Helm Chart value file (required due Outpost specific configs)

```bash
cat<<EOF > ebs-helm-values.yaml 
---
image:
  repository: 779385874783.dkr.ecr.us-west-2.amazonaws.com/ecr-public/ebs-csi-driver/aws-ebs-csi-driver

sidecars:
  provisioner:
    image:
      repository: 779385874783.dkr.ecr.us-west-2.amazonaws.com/ecr-public/eks-distro/kubernetes-csi/external-provisioner
  attacher:
    image:
      repository: 779385874783.dkr.ecr.us-west-2.amazonaws.com/ecr-public/eks-distro/kubernetes-csi/external-attacher
  snapshotter:
    image:
      repository: 779385874783.dkr.ecr.us-west-2.amazonaws.com/ecr-public/eks-distro/kubernetes-csi/external-snapshotter/csi-snapshotter
  livenessProbe:
    image:
      repository: 779385874783.dkr.ecr.us-west-2.amazonaws.com/ecr-public/eks-distro/kubernetes-csi/livenessprobe
  resizer:
    image:
      repository: 779385874783.dkr.ecr.us-west-2.amazonaws.com/ecr-public/eks-distro/kubernetes-csi/external-resizer
  nodeDriverRegistrar:
    image:
      repository: 779385874783.dkr.ecr.us-west-2.amazonaws.com/ecr-public/eks-distro/kubernetes-csi/node-driver-registrar
  volumemodifier:
    image:
      repository: 779385874783.dkr.ecr.us-west-2.amazonaws.com/ecr-public/ebs-csi-driver/volume-modifier-for-k8s

node:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: node-role.kubernetes.io/control-plane
                operator: DoesNotExist
              - key: eks.amazonaws.com/compute-type
                operator: NotIn
                values:
                  - fargate
              - key: node.kubernetes.io/instance-type
                operator: NotIn
                values:
                  - a1.medium
                  - a1.large
                  - a1.xlarge
                  - a1.2xlarge
                  - a1.4xlarge

storageClasses:
  - name: ebs-gp2
    annotations:
      storageclass.kubernetes.io/is-default-class: "true"
    volumeBindingMode: WaitForFirstConsumer
    reclaimPolicy: Retain
    parameters:
      encrypted: "false"
      type: gp2
EOF
```

3.1.2. Install the Helm Chart using the value file

```bash
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update
helm upgrade --install aws-ebs-csi-driver --namespace kube-system aws-ebs-csi-driver/aws-ebs-csi-driver --values ebs-helm-values.yaml
```

3.1.3. Verify that all pods are running

```bash
kubectl get pod -n kube-system -l "app.kubernetes.io/name=aws-ebs-csi-driver,app.kubernetes.io/instance=aws-ebs-csi-driver"
```

3.2 Deploy AWS LB Controller

3.2.1. Create the EBS Helm Chart value file (required due Outpost specific configs)

```bash
cat<<EOF > lb-helm-values.yaml
clusterName: lab-outpost-local

image:
  repository: 779385874783.dkr.ecr.us-west-2.amazonaws.com/ecr-public/eks/aws-load-balancer-controller

enableShield: false
enableWaf: false
enableWafv2: false
EOF
```

3.2.2. Install the Helm Chart using the value file

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --values lb-helm-values.yaml
```

3.3. Deploy Amazon CloudWatch Observability Add-on

3.3.1. Create the EBS Helm Chart value file (required due Outpost specific configs). The specific tag for CWAgent is required due a TLS issue with the newer versions (no root cause identified).

```bash
cat<<EOF > cw-helm-values.yaml
clusterName: lab-outpost-local

region: us-west-2

containerLogs:
  fluentBit:
    image:
      repositoryDomainMap:
        public: 779385874783.dkr.ecr.us-west-2.amazonaws.com/ecr-public/aws-observability

manager:
  image:
    repositoryDomainMap:
      public: 779385874783.dkr.ecr.us-west-2.amazonaws.com/ecr-public/cloudwatch-agent

agent:
  image:
    tag: 1.247360.0b252689
    repositoryDomainMap:
      public: 779385874783.dkr.ecr.us-west-2.amazonaws.com/ecr-public/cloudwatch-agent
EOF
```

3.3.2. Install the Helm Chart using the value file

```bash
helm repo add aws-observability https://aws-observability.github.io/helm-charts
helm repo update
helm upgrade --install --create-namespace --namespace amazon-cloudwatch amazon-cloudwatch-observability aws-observability/amazon-cloudwatch-observability  --values cw-helm-values.yaml
```

3.3.3. Apply these patches to avoid having the FluentBit/CWAgent running on EKS control-plane nodes (not able to configure these on Helm Chart Values). This is required because control-plane nodes doesn't have CNI ready nor IAM Polcies required for CW.

```bash 
kubectl -n amazon-cloudwatch patch daemonset cloudwatch-agent --type=json -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/affinity",
    "value": {
      "nodeAffinity": {
        "requiredDuringSchedulingIgnoredDuringExecution": {
          "nodeSelectorTerms": [
            {
              "matchExpressions": [
                {
                  "key": "node-role.kubernetes.io/control-plane",
                  "operator": "DoesNotExist",
                }
              ]
            }
          ]
        }
      }
    }
  }
]'

kubectl -n amazon-cloudwatch patch daemonset fluent-bit --type=json -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/affinity",
    "value": {
      "nodeAffinity": {
        "requiredDuringSchedulingIgnoredDuringExecution": {
          "nodeSelectorTerms": [
            {
              "matchExpressions": [
                {
                  "key": "node-role.kubernetes.io/control-plane",
                  "operator": "DoesNotExist",
                }
              ]
            }
          ]
        }
      }
    }
  }
]'
```

3.3.5. Edit CWAgent image tag and FluentBit ConfigMap (https://t.corp.amazon.com/V1387280854/communication).

```bash
kubectl edit cm -n amazon-cloudwatch  fluent-bit-config
kubectl edit amazoncloudwatchagents.cloudwatch.aws.amazon.com cloudwatch-agent -n amazon-cloudwatch -o yaml
```

3.4. Deploy Kubernetes Metrics Server

3.4.1. Create the EBS Helm Chart value file (required due Outpost specific configs)

```bash
cat<<EOF > ms-helm-values.yaml
image:
  repository: 779385874783.dkr.ecr.us-west-2.amazonaws.com/k8s/metrics-server/metrics-server

args:
  - --kubelet-insecure-tls
EOF
```

3.4.2. Install the Helm Chart using the value file

```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
helm upgrade --install metrics-server --namespace kube-system metrics-server/metrics-server --values ms-helm-values.yaml
```
