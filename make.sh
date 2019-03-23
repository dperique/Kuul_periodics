# File to generate the yamls for Kuul Jobs using template.yaml
#
cat template.yaml | sed 's/THE_NAME/job1-staging/' | sed 's/THE_MINUTE/15/'  | sed 's/THE_SCRIPT/print_stuff.sh/' | sed 's/THE_TARGET/staging1/' > pjob1-staging1.yaml
cat template.yaml | sed 's/THE_NAME/job2-staging/' | sed 's/THE_MINUTE/30/'  | sed 's/THE_SCRIPT/print_more.sh/'  | sed 's/THE_TARGET/staging2/' > pjob2-staging2.yaml
