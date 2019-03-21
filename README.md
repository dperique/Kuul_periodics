# Kuul Periodics

## The use-case

When running an software operation, there are times when you want to run periodic scripts or
periodic "jobs".  This includes:

* Running automated software deployments
* Running automated software sanity checks
* Running automated tests to ensure the your service is running well
* Running automated backups of databases

Once tool that can be used is Zuul.  Zuul runs jobs on nodepool workers.  Nodepool workers
are VMs spun up on Openstack clusters.  Jobs run on the nodepool workers and then they are
destroyed and recycled for the next job.

Zuul can also do things like run CI tests on demand -- this is a non-goal for the Kuul Periodics
project.

Kubernetes is a nice platform for running containers.  My thought is that nodepool workers
can be slimmed down into containers and instead of running VMs on Openstack, we can run the
containers on Kubernetes -- hence the name Kuul as a play on the word Zuul.

## Kuul Images

Every periodic job needs a docker image.  I call these images "Kuul Images".  For whatever
script you want to run, create your container for it -- try to make it as small as possible.

## Kuul k8s cluster

Once you have docker images that you want to run, you will have to create a k8s cluster upon
which to run them.  I call this the "Kuul k8s cluster".

If you want to have multiple Kuul k8s clusters, go ahead and make them.  This will be good
for having more than one Kuul system to run your periodic jobs - in case one of them has
a problem or you want to experiment with one without affecting another one supporting, say,
production operations.

Also, the Kuul k8s cluster can be made up of different types of k8s nodes; each node can have
certain characteristics.  For example:

* nodes that can talk to "internal only" environments (staging, dev) and can access only
  internal networks.
* nodes that can talk to production environments and can access production networks.

We use the concept of nodeSelector in Kubernetes to let periodic jobs land on certain k8s
nodes as we see fit.

## Yamls and the Kubernetes cronjob

We implement periodic jobs uring the Kubernetes cronjob construct.  This contruct is very
much like processes that run using Linux cron.

We are setup the yamls so that we are careful to select the k8s nodes upon which to run and
limit how much CPU and RAM we allow the jobs to use.

## Monitoring your jobs

We monitor our jobs using kubectl commands.  This makes sense because the jobs are really
Kubernetes jobs which are really Kubernetes pods.

In order to monitor the pods in a more user friendly way, we use k9s.  If you want to see
the logs of runnign jobs, just use k9s commands to see the logs.  If you want to edit the
periodic jobs (including their schedule), just edit the cronjob construct using k9s.  K9s is
a nice too to use but there is nothing preventing you from just doing the same things with
the kubectl command.
