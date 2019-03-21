for i in $(kubectl get po -a| grep Completed|awk '{print $1}' | grep -e str1 -e str2) ; do
  echo $i

  kubectl delete po $i
done
