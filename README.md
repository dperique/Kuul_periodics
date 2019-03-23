# Kuul Periodics

## The use-case

When running a software operation, there are times when you want to run periodic scripts or
periodic "jobs".  This includes:

* Running automated software deployments
* Running automated software sanity checks
* Running automated tests to ensure the your service is running well
* Running automated backups of databases

One tool that can be used is Zuul.  Zuul runs jobs on nodepool workers.  Nodepool workers
are VMs spun up on Openstack clusters.  Jobs run on the nodepool workers and then they are
destroyed and recycled for the next job.

Zuul can also do things like run CI tests on demand -- CI testing is a non-goal for the
Kuul Periodics project.

Kubernetes is a nice platform for running containers.  My thought is that nodepool workers
can be slimmed down into containers and instead of running VMs on Openstack, we can run the
containers on Kubernetes -- hence the name "Kuul" as a play on the word "Zuul".

The implementation of the Kuul project is really just another use of Kubernetes.  As such
we can take advantage of the vast amount of documentation already in existence.  The only
thing that is unique to each Kuul Periodics deployment is:

* the custom Kuul Images
  * These are built by the teams using them and will be very specific to their environment
  * The images are just docker images that can be tested by running them using plain docker
* the method used to deploy the CronJob yamls (a Kubernetes construct)
  * This can be automated or manual

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
* Use `kubectl editi ...` or `kubectl apply ...` to
  * Suspend periodic jobs by changing the `suspend` pod parameter. This allows us to
    quickly suspend and resume jobs for scheduling.  This is useful when you need to perform
    maintenance and want to stop running the periodic jobs and then to resume them when the
    maintenance is complete.
* Change the job schedule by changing the `schedule` parameter.  This is useful when you want
  to run a job immediately to debug it (just change the `schedule` parameter to the next minute)
  or when you want to just re-arrange the schedule.

Here is a list of CronJob characteristics to keep in mind:

* When a CronJob runs, it starts up a Kubernetes Job
* When a Kubernetes Job starts, it starts up a Kubernetes Pod to run your script
* The Kubernetes Pod is the entity doing the actual work of running the script
* If you delete a Pod in Running state, it will restart until the Pod gets to Complete state
* If you want to stop a CronJob -- i.e., stop the Pod from running:
  * Delete the CronJob (or set the `Suspend` field to `true`)
  * Delete the Job that the CronJob started
    * the pod will be Terminated


## Kuul Images

Every periodic job needs a docker image.  I call these images "Kuul Images".  For whatever
script you want to run, create your container for it -- try to make the container as small as
possible to help with scalability.  You will also need a docker registry where you can
push your images and where Kubernetes can pull the images from.

The container can run arbitray things.  I like to keep the implementation of the Kuul Periodics
and the Kuul Images separate.  The Kuul Periodics system just runs the image and does not care
what it does.  I expect people to use the Kuul Periodics system but to have a separate repo
and build process for their custom Kuul Images.

See the [Example Kuul Image](https://github.com/dperique/Kuul_image_example)

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

We implement periodic jobs uring the Kubernetes CronJob construct.  This contruct is very
much like processes that run using Linux cron.

The jobs are specified in yamls.  The lifecycle goes something like this:

* Create a yaml template for certain jobs; use names that help you uniquely identify jobs
  so that you can easily delete them by filtering them effectively (for example by using
  the `grep` command)
* Instantiate that template
  * See template.yaml in this repo
  * See make.sh in this repo
    * this is a simple script that can use the template to instantiate a CronJob.  Feel
      free to embelish upon this concept by using tools with more powerful templating
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
  * Automate creting the Kuul k8s cluster
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
  * Upon merge of PRs that add new jobs, have automation that instantiates the templates and
    applies them to the Kuul k8s cluster.
  * Upon merge of PRs that remove jobs, have automation that removes the CronJobs from the
    Kuul k8s cluster.
  * The repo should have a way to add default nodeSelector labels or other labels for CronJobs
    that need to run on custom k8s nodes.


## Monitoring and Editing Your Jobs

Monitor jobs using `kubectl` commands.  This makes sense because the jobs are really
Kubernetes Jobs which are really Kubernetes Pods.

In order to monitor the Pods in a more user friendly way, we can use the
[Kubernetes dashboard](https://github.com/kubernetes/dashboard)
or a tool like [k9s](https://github.com/derailed/k9s). But either way, you are still using
the `kubectl` command to manage the Jobs.

If you want to:

* see the logs of running Jobs, just use k9s commands to see the logs
  * or `kubectl logs ...`
* edit the periodic jobs (including their schedule) using one of these methods:
  * Use the "edit" function in k9s
  * Use `kubectl edit ...`
    * look for `suspend` variable set to `true` or `false` to suspend or resume the job
      * kubectl patch cronjobs (aJobName) -p '{"spec" : {"suspend" : true }}'
        * Currently running jobs will continue until done
        * You can delete the job if you want to get rid of it immediately via `kubectl delete job`
          and `kubectl delete po`
    * look for `schedule` to set a cron-like schedule
      * `kubectl patch cronjobs (aJobName) -p '{"spec" : {"schedule" : "30 * * * *" }}'`
    * look for `concurrencyPolicy` to set whether you're ok with "overlapping" jobs
    * look for `nodeSelector` to pick which k8s node you want to run your jobs on
      * Use `kubectl label node --overwrite (aNode) myTag=label` to label your node
    * look for `successfulJobsHistoryLimit` to change how many jobs to retain
      * `kubectl patch cronjobs (aJobName) -p '{"spec" : {"successfulJobsHistoryLimit" : "(aNum)"}}'`
      * if the change is less than the jobs retained, it will remove the old pods
    * look for `failedJobsHistoryLimit` to change how many failed jobs you want to retain
      * `kubectl patch cronjobs (aJobName) -p '{"spec" : {"failedJobsHistoryLimit" : "(aNum)"}}'`
      * if the change is less than the jobs retained, it will remove the old pods
  * Edit your template(s) and then run `kubectl apply -f ...`


## Utilities

This is how I check the labels on my k8s nodes:

```
# Label some nodes.
#
kubectl label node --overwrite node-1 myTag=periodic`
kubectl label node --overwrite node-3 myTag=periodic`

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
