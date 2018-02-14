function install_helm {
 cd /tmp
 wget https://storage.googleapis.com/kubernetes-helm/helm-v2.8.0-linux-amd64.tar.gz 
 tar xfz helm-v2.8.0-linux-amd64.tar.gz
 mv linux-amd64/helm /usr/local/bin
}

function setup_helm {
  kubectl create serviceaccount tiller --namespace kube-system
cat <<EOF > /tmp/tiller.yml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tiller
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: tiller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: tiller
    namespace: kube-system

EOF
  kubectl apply -f /tmp/tiller.yml

  helm init --service-account tiller

  until kubectl rollout status deployment/tiller-deploy -n kube-system
  do
    echo "waiting for tiller deployment"
  done
}

function setup_autoscaler {
  cat <<EOF > /tmp/autoscaler.yml
autoscalingGroups:
  - name: ${node_asg_name}
    maxSize: ${node_asg_max}
    minSize: ${node_asg_min}
tolerations:
  - effect: NoSchedule
    key: node-role.kubernetes.io/master
    operator: Exists
rbac:
    create: true
nodeSelector:
    node-role.kubernetes.io/master: ""
awsRegion: eu-central-1
EOF
  if [ -n "$http_proxy" ]; then
    echo "proxy: \"$(cat /etc/terraform/load_balancer_dns):3128\"" >> /tmp/autoscaler.yml
  fi

  cat <<EOF > /tmp/autoscaler_patch
--- cluster-autoscaler/templates/deployment.yaml	1970-01-01 00:00:00.000000000 +0000
+++ cluster-autoscaler2/templates/deployment.yaml	2018-01-31 11:19:27.888363305 +0000
@@ -42,6 +42,12 @@
             - --{{ $key }}{{ if $value }}={{ $value }}{{ end }}
           {{- end }}
           env:
+          {{- if .Values.proxy }}
+            - name: HTTP_PROXY
+              value: "{{ .Values.proxy }}"
+            - name: HTTPS_PROXY
+              value: "{{ .Values.proxy }}"
+          {{- end }}
           {{- if eq .Values.cloudProvider "aws" }}
             - name: AWS_REGION
               value: "{{ .Values.awsRegion }}"
EOF

  cd /tmp
  helm fetch stable/cluster-autoscaler --version=0.4.1
  tar xfz cluster-autoscaler-0.4.1.tgz

  patch cluster-autoscaler/templates/deployment.yaml < /tmp/autoscaler_patch

  helm install ./cluster-autoscaler --name autoscaler -f /tmp/autoscaler.yml --namespace kube-system
}

install_helm
setup_helm
setup_autoscaler