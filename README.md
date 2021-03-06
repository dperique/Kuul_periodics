# The Kuul Periodic System

The "Kuul Periodic System" is a fancy name for a Kubernetes cluster that runs periodic
jobs using Kubernetes CronJobs.

## The use-case

When running a software operation, there are times when you want to run periodic scripts or
periodic "jobs".  This includes:

* Running automated software deployments
* Running automated software sanity checks
* Running automated tests to ensure the your service is running well
* Running automated backups of databases

## Comparison with Zuul

One tool that can be used for running periodic jobs is Zuul.  Zuul runs jobs on nodepool workers.
Nodepool workers are VMs spun up on Openstack clusters.  Jobs run on the nodepool workers and
then they are destroyed and recycled for the next job.

Zuul can also do things like run CI tests on demand -- CI testing is a non-goal for the
Kuul Periodics project.

Kubernetes is a nice platform for running containers.  My thought is that nodepool workers
can be slimmed down into containers and instead of running VMs on Openstack, we can run the
containers on Kubernetes -- hence the name "Kuul" as a play on the word "Zuul".

## Why Not Just Run Cron?

I ran Linux cron -- for a while.  I had several Ubuntu VMs with cron installed and ran various
jobs on them.  This worked out well for a while.
Eventually, as the number of jobs grew, I started writing scripts to tell what jobs were
running on what VMs; the script kept track of the IPs of the VMs.  I then had to deal with
coordinating things so I don't accidentally
run the same job on more than one machine.  I also had to fight with cron because it will
run another instance of a jobs regardless of whether its finished or not.  The turning point
for me was when I ran out of
VMs to run jobs and needed to spin up more since running more than one job on a VM was not
an option because the jobs were using the `/tmp` directory and "colliding" with each other.
The management of the cron jobs and VMs was getting very cumbersome.

So my next step was to containerize my jobs.  This worked out well but then I was creating
multiple containers on the VMs and having to manage even more things (VMs and containers).
This was when I decided to use the idea of the "Kuul Periodic System".

Kubernetes manages my job containers as Pods running on Kubernetes nodes.  My Ubuntu VMs
have since been converted over to Kubernetes nodes.  Now, I let Kubernetes manage my
VMs and jobs.

## Where's the User Manual?

The implementation of the Kuul project is really just another use of Kubernetes.  As such
we can take advantage of the vast amount of documentation already in existence.  The only
thing that is unique to each Kuul Periodics deployment is:

* the custom Kuul Images
  * These are built by the teams using them and will be very specific to their environment
  * The images are just docker images that can be tested by running them using plain docker
* the method used to deploy the CronJob yamls (a Kubernetes construct)
  * This can be automated or manual
  * The "make.sh" file this repo is a rudimentary example of how to automate creating your
    Kuul jobs.

Learning how to use a Kuul Periodic System to run your jubs comes down to learning how to
create, monitor, and manage Kubernetes CronJobs.  So, you are not going to find a comprehensive
user manual specifically for the Kuul Periodic System.  If you don't know how to use Kubernetes
and the kubectl command, you should stop here and learn that first (perhaps you can start
with [minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/).

Here's a [doc on Kubernetes CronJobs](https://unofficial-kubernetes.readthedocs.io/en/latest/concepts/jobs/cron-jobs/)

## Jobs are implemented as Kubernetes CronJobs

The periodic jobs are implemented as Kubernetes CronJobs.  This allow us to:

* Run containers on a certain schedule (like what we can do with cron)
* Retain jobs that finished (including logs).  After the jobs are done, the pods are
  left behind by default.  You can retrieve the logs as needed and "page through" different
  pods/jobs that ran in the past to help you see how things may have changed (in the case
  where you are trying to figure out when something stopped working).  The number of failed
  and succeeded jobs retained is configurable and you can delete the pods when you need to --
  for example, when you don't need them anymore or if they consume too many resources.
* Use nodeSelectors to choose which k8s nodes the jobs run on.
* Have control to prevent a job from running again when the current one has not finished.
  This feature is missing when running regular cron because if a job is already running
  and it's time to launch another job, cron will launch it regardless of if the current job
  is running or not.
* Use `kubectl edit ...` or `kubectl apply ...` to
  * Suspend periodic jobs by changing the `suspend` CronJob parameter. This allows us to
    quickly suspend and resume jobs for scheduling.  This is useful when you need to perform
    maintenance and want to stop running the periodic jobs and then resume them when the
    maintenance is complete.  If a CronJob is set to suspended, it remains suspended even if
    the yaml is re-applied using kubectl.
* Change the job schedule by changing the `schedule` parameter.  This is useful when you want
  to run a job immediately to debug it (just change the `schedule` parameter to the next minute)
  or when you want to just re-arrange the schedule.

Here is a list of CronJob characteristics to keep in mind:

* When a CronJob runs, it starts up a Kubernetes Job
* When a Kubernetes Job starts, it starts up a Kubernetes Pod to run your script
* The Kubernetes Pod is the entity doing the actual work of running the script
* If you delete a Pod in Running state, the Job that started it will restart the Pod until
  the Pod gets to Complete state
* If you want to stop a CronJob -- i.e., stop the Pod from running:
  * Delete the CronJob (or set the `Suspend` field to `true`)
  * Delete the Job that the CronJob started
    * the Pod will be Terminated
* If the container image is such that when the job "fails", have some way to report failure
  (e.g., report in a slack channel or log) but do NOT `exit 1` in the Pod -- if you do, the
  job will end with status of Error and will run again and repeat until a return code of
  0 is returned.  I'm still experimenting to see if this implies anything but a return code
  of 0 is ok.


## Kuul Images

Every periodic job needs a docker image.  I call these images "Kuul Images".  For whatever
script you want to run, create your container for it -- try to make the container as small as
possible to help with scalability.  You will also need a docker registry where you can
push your images and where Kubernetes can pull the images from.

The container can run arbitray things.  I like to keep the implementation of the Kuul Periodics
and the Kuul Images separate.  The Kuul Periodics system just runs the image and does not care
what it does.  I expect people to use the Kuul Periodics system but to have a separate repo
and build process for their custom Kuul Images.

See the [Example Kuul Image](https://github.com/dperique/Kuul_image_example) and how I built
it and ran it on my Kuul k8s cluster.

## Kuul k8s cluster

Once you have Kuul Images that you want to run, you will have to create a k8s cluster upon
which to run them.  I call this the "Kuul k8s cluster".

Creating your Kubernetes cluster can be done using something like
[Kubespary](https://github.com/kubernetes-incubator/kubespray)

I recommend that you eventually have multiple Kuul k8s clusters.  This will be good
for having more than one Kuul system to run your periodic jobs for the following reasons:

* In case one of your Kuul Periodic Systems has a problem and becomes unusable (this eliminates
  a single point of failure for running periodic jobs)
* You want to experiment with something without affecting another Kuul Periodic System that is
  running jobs for production operations.
* You just want a separate system for other reasons.

The Kuul k8s cluster can be made up of different types of k8s nodes; each node can have
certain characteristics.  For example:

* nodes that can talk to "internal only" environments (staging, dev) and can access only
  internal networks.
* nodes that can talk to production environments and can access production networks.

We use the concept of nodeSelector in Kubernetes to let periodic jobs land on certain k8s
nodes as we see fit.  We also use the Pod constructs to limit cpu and memory of the jobs to
avoid runaway jobs consuming too many resources.

## Yamls and the Kubernetes CronJobs

We implement periodic jobs using the Kubernetes CronJob construct.  This contruct is very
much like processes that run using Linux cron.

The jobs are specified in yamls.  The lifecycle goes something like this:

* Create a yaml template for certain jobs; use names that help you uniquely identify jobs
  so that you can easily find them by filtering for them effectively (for example by using
  the `grep` command)
* Instantiate that template
  * See template.yaml in this repo
  * See make.sh in this repo
    * this is a simple script that can use the template to instantiate a CronJob.  Feel
      free to embellish upon this concept by using tools with more powerful templating
      capabilities such as Ansible and Jinja
* `kubectl config use-context (aK8s)` for your Kuul k8s cluster
* `kubectl apply -f .` your templates
* Modify and redeploy your yamls as needed.
* Let the jobs run
* Look at logs of previous jobs or forward the logs to a logserver for persistent storage
* Delete any old Jobs and Pods you don't need
* If your Kuul k8s cluster needs more resources, add more k8s nodes

## CronJob Lifecycle Automation

I recommend developing automation for your CronJobs to help keep things simple as the number of
jobs grows.  Here is an example method I use:

* Automate creating and maintaining the Kuul k8s cluster
  * Automate creating the Kuul k8s cluster
  * Automation the adding of new k8s nodes to your Kuul k8s cluster.
    * Automate the addition of plain k8s nodes
      * Add in the appropriate nodeSelector label for CronJobs that need to run on these k8s
    * Automate the addition of custom k8s nodes (e.g., nodes that need special networking
      or other unique resources)
      * Add in the appropriate nodeSelector label for CronJobs that need to run on these k8s
        nodes

* Automate the instantiation of CronJob templates and applying them to the Kuul k8s cluster
  * Create a repo for adding new Kuul jobs
    * This could be adding more lines to your list of jobs that use templates
  * Upon merge of PRs that add new jobs, let the automation instantiate the templates and
    apply them to the Kuul k8s cluster.
  * Upon merge of PRs that remove jobs, let the automation remove the CronJobs from the
    Kuul k8s cluster.
  * The repo should have a way to add default nodeSelector labels or other labels for CronJobs
    that need to run on custom k8s nodes.


## Monitoring and Editing Your Jobs

Monitor jobs using `kubectl` commands.  This makes sense because the jobs are really
Kubernetes CronJobs which make Jobs which make Pods.

In order to monitor the Pods in a more user friendly way, we can use the
[Kubernetes dashboard](https://github.com/kubernetes/dashboard)
or a tool like [k9s](https://github.com/derailed/k9s). But either way, you are still using
the Kubernetes apiserver (e.g., `kubectl` command) to manage the Jobs.

In my opinion, because the Kuul Periodic System will be used to run your periodic jobs
and because (for the most part), no one really cares how it's implemented, you will want
to use a simple UI that allows you to monitor or trigger jobs.  In this case, I highly
recommend you use something like k9s.

In my case, I created a Kuul Periodic System (k8s cluster) with 3 Kubernetes masters, setup
3 machines running k9s and let users monitor the jobs like that.  Each machine sends
Kubernetes apiserver calls to a different Kubernetes master (to help spread the load).
This avoids users having to install k9s and gives a single and simple UI.  The machines are
setup so that when you login, you can have a read-only user (for those who just want to
watch and view logs) and a read-write user (for those who want to delete/add/trigger jobs).

If you want to:

* see the logs of running Jobs, use k9s commands to see the logs
  * or `kubectl logs ...`
* edit the periodic jobs (including their schedule) using one of these methods:
  * Use the "edit" function in k9s
  * Use `kubectl edit ...`
    * look for `suspend` variable set to `true` or `false` to suspend or resume the job
      * Or use something like `kubectl patch cronjobs (aJobName) -p '{"spec" : {"suspend" : true }}'`
      * Currently running jobs will continue until done
      * You can delete the job if you want to get rid of it immediately via `kubectl delete job`
        and `kubectl delete po`
    * look for `schedule` to set a cron-like schedule
      * Or use something like `kubectl patch cronjobs (aJobName) -p '{"spec" : {"schedule" : "30 * * * *" }}'`
    * look for `concurrencyPolicy` to set whether you're ok with "overlapping" jobs
    * look for `nodeSelector` to pick which k8s node you want to run your jobs on
      * Use `kubectl label node --overwrite (aNode) myTag=label` to label your node
    * look for `successfulJobsHistoryLimit` to change how many jobs to retain
      * Or use something like `kubectl patch cronjobs (aJobName) -p '{"spec" : {"successfulJobsHistoryLimit" : "(aNum)"}}'`
      * if the number you set is less than the current number of Jobs retained, old Jobs/Pods are removed
    * look for `failedJobsHistoryLimit` to change how many failed jobs you want to retain
      * Or use something like `kubectl patch cronjobs (aJobName) -p '{"spec" : {"failedJobsHistoryLimit" : "(aNum)"}}'`
      * if the number you set is less than the current number of Jobs retained, old Jobs/Pods are removed
  * Edit your template(s) and then run `kubectl apply -f ...`

## Production Kuul Periodic Systems: use Service Account

For production systems, make it so that the default access is read-only as you don't
want just anybody going in there and making arbitrary changes.

You can do this by applying the kuul-service-account.yaml (after filling it in with your
Kuul k8s cluster name).  The concept is borrows heavily from this
[script for adding k8s read-only access](https://github.com/dperique/Kubernetes_clusterrole).

The idea is to create a service account which is tied to a ClusterRole with limited privileges and
then build a kubectl context using that.

## Utilities

This is how you can sort by the schedule:

```
kubectl get cronjob -o wide --sort-by=.spec.schedule
```

This is how I check the labels on my k8s nodes:

```
# Label some nodes.
#
kubectl label node --overwrite node-1 myTag=periodic`
kubectl label node --overwrite node-3 myTag=periodic`

# Unlabel a node.
#
kubectl label node --overwrite node-3 myTag-`

# Grep for the label quickly see what nodes are using that label.
#
for i in 1 2 3 4 5 ; do echo $i ;kubectl describe node node-$i | grep periodic ; done
```

How I get rid of old and Completed Jobs.  The `str1` and `str2` are strings used to uniquely
identify Pods that are Jobs that are ok to delete.

NOTE: you can also remove old Jobs in Completed state by modifying the `successfulJobsHistoryLimit`
and `failedJobsHistoryLimit` in the CronJob spec.

```
for i in $(kubectl get po -a| grep Completed|awk '{print $1}' | grep -e str1 -e str2 ) ; do
  echo $i
  kubectl delete po $i
done
```

Ways to delete Jobs (not tested):

```
kubectl delete job $(kubectl get job -o=jsonpath='{.items[?(@.status.succeeded==1)].metadata.name}')
kubectl get jobs --all-namespaces | sed '1d' | awk '{ print $2, "--namespace", $1 }'
loop and delete the jobs
```

## Appendix: Kuul Periodic System Maintenance

The Kuul Peridic System will keep running but will need regular maintenance to avoid clutter.

Specifically:

* When people manually trigger jobs, delete them after they are done
* If there are Error Pods, delete them eventually
* Check the list of Jobs and see what's been around and for how long.  Delete Jobs that have
  been around for many days and show completions of "0/1".  Jobs that didn't complete were
  probably due to an error condition which may have been corrected many days ago.  if the
  "0/1" jobs keep showing up, investigate and fix it.

Once in a while, look at all the CronJobs to see the "Last Scheduled" time
for each CronJob.  If you jobs should run hourly, you need to ensure that the last scheduled time
does not exceed an hour.  If it does, this means a job has not been scheduled (which implies
someone needs to look into it).

Check the logs for the Kubernetes controller pods in the kube-system namespace.  Ensure there are
no jobs being skipped.  If there are skipped jobs, delete and re-apply them will usually fix the
problem.  If not, you'll have to do some debugging.

* kubectl delete/apply of the CronJob usually fixes the problem
* In the future, we may consider setting`startDeadlineSeconds` to account for clock skew in case
  that's the reason a Cronjob was not triggered.

We have seen a symptom where after getting logs on a live Pod running a script (by pressing the
lowercase L in k8s), we see an error like `failed to watch file
"/var/log/pods/91149b09-66c4-11e9-abd5-06bc3661cf0f/k8s-lon04/0.log":
no space left on device`.  We have not determined the root cause but highly suspect that it's
due to some resource not being free'ed (including inodes in the filesysem).  Remember, the Kuul
Periodic System is constantly starting and deleting Jobs/Pods so leaks are more easily exposed.

* We have found the best way to mitigate this problem is to cordon the worker k8s node having
  this problem, wait for all Pods to finish running, reboot, and uncordon.
* To be proactive about this problem and prevent it altogether, you can cordon/wait/reboot/uncordon
  any of the Kuul worker nodes regularly to keep them fresh.

* Every N days, the k8s worker nodes will get to about 80% disk usage resulting in "disk pressure" events
  on the node.  This is normal because Kubernetes is constantly running jobs and has to do garbage
  collection for dead Pods (i.e., finished Jobs).  Kubernetes will attempt to cleanout unused images and
  free space.  I have seen happen several times and each time, I did nothing.  In once case, I saw the
  k8s worker node diskspace usage go from 80% to around 29%.

  * To help reduce any stress from seeing the events, we use k8s worker nodes with a good amount of
    disk space; this symptom will not disappear but take longer to happen and when it does happen,
    there will be much more disk to use during the automatic recovery.

Automated Maintenance:

* Shut down the Kuul Periodic System for maintenance and delete/apply every
  job regularly (e.g., every week depending on how often kube controller problems happen).
  Delete and re-apply all CronJobs while preserving the "suspend" state of each job.  This will
  proactively address any kube controller issues.

* Cordon one worker node every few days and after some
  amount of time, reboot/uncordon it.  The time to wait can be something that guarantees no jobs
  are running (e.g., if you run periodic jobs that take 20 minutes, then wait 3 hours) or you
  can check for any running Pods (preferred approach) before rebooting.  Do this
  for every node and you may never see the "no space left" symptom.

* Delete all manually triggered Jobs and Pods after a certain age regularly.

* Look for Error Pods and report them regularly; this will help alert someone to investigate
  them close to when they happen so you can debug symptoms soon after they occur.

* Create a "check_jobs" CronJob that checks various things to ensure your Kuul Periodic System
  is running well.  For example, check to see that there are N jobs completed every hour.  If
  not all jobs are accounted for, this will let you know something is wrong.

## TODO

Some thoughts about things I want to add here:

* Explore `activeDeadlineSeconds` so that I can limit how long a job runs. Need to test it to ensure
  it actually works as expected.
* Explore `startDeadlineSeconds` so that we can only run jobs when there's enough time so they don't
  collide with other jobs that happen after that job.  For example, a deploy job runs top of hour and
  test job runs at bottom of hour and deploy job takes max of 20 minutes to run, we can set
  `startDeadlineSeconds` to 600.
