#!/usr/bin/env bash

set -e

if ! which jq > /dev/null; then
  echo "jq required but not found"
fi

fetch_all_projects_url='https://www.bostonplans.org/projects/development-projects?projectstatus=under+review&sortby=name&type=dev&viewall=1'

for project_slug in $(curl -s "${fetch_all_projects_url}" \
  | grep '/projects/development-projects/' \
  | grep -v '/rss' \
  | grep -o '"[^"]*"' \
  | sed 's/"//g' \
  | cut -d/ -f4)
do
  if [ -f supported-projects ] && grep -q "^${project_slug}$" supported-projects; then
    echo "Skipping already supported project: ${project_slug}"
    continue
  fi

  if [ -f missed-projects ] && grep -q "^${project_slug}$" missed-projects; then
    echo "Skipping already missed project: ${project_slug}"
    continue
  fi

  # set -x

  project_data=$(curl -s "https://www.bostonplans.org/projects/development-projects/${project_slug}")
  project_id=$(echo "${project_data}" \
    | grep timeline-project-id \
    | grep -o '>[0-9]\+<' \
    | sed 's/[<>]*//g')
  timeline_container_version=$(echo "${project_data}" | grep -i my-timeline-container | grep -o '".*"' | sed 's/"//g')

  if [[ "${timeline_container_version}" == 'my-timeline-container-v2' ]]; then
    sf_projects_response=$(curl -s "https://www.bostonplans.org/BRAComponents/Handlers/SalesforceProjects.ashx?pid=${project_id}")
  else
    sf_projects_response=$(curl -s "https://www.bostonplans.org/BRAComponents/Handlers/SalesforceProjects_v1.ashx?pid=${project_id}")
  fi
  # echo "sf_projects (pid: ${project_id}): $sf_projects"

  # set +x

  comment_period_data=$(echo $sf_projects_response | jq '. | map(select(.tags[] | contains ("ty_Comment Period")))') || \
    (echo "Error handling ${project_slug}/${project_id}. Skipping" && continue)

  comment_period_names=$(echo $comment_period_data | jq '(. | .[] .user.name)')

  if ! echo $comment_period_data | grep -q Open; then
    echo "Comment period not yet open: ${project_slug}"
    continue
  fi

  if ! echo $comment_period_data | jq '(. | .[] .text)' | grep -q 'The comment period is currently open'; then
    echo "Storing missed project: ${project_slug}"
    echo "${project_slug}" >> missed-projects
    continue
  fi

  echo "Storing supported project: ${project_slug}"
  echo "${project_slug}" >> supported-projects

  sleep 1
done
