# dashing-jira-burndown
Jira burndown plugin for dashing

## Description

GitHub location: https://github.com/vossim/dashing-jira-burndown

[Dashing](http://shopify.github.com/dashing) widget to display a [Jira](https://www.atlassian.com/software/jira) (greenhopper) burn-down, rotating the last X sprints for a specific rapidView (where X is configurable)

Example of a burndown:

![Image](../master/jira_burndown.png?raw=true)

## Installation

Put the files `jira_burndown.coffee`, `jira_burndown.html` and `jira_burndown.scss` in the `/widget/jira_burndown` directory and the files `jira_burndown.rb` and (optionally) `jira_burndown.yaml` in the `/jobs` directory

You also need the `c3.min.js` and `d3.min.js` files in the `/assets/javascripts` directory and the `c3.min.css` file in the `/assets/stylesheets` directory.

## Job configuration

Required configuration:
* `jira_url`: Url to your jira server, excluding the trailing slash (/)
* `username`: Username for a user with sufficient rights on your jira server
* `password`: Password for the user
* `numberOfSprintsToShow`: The number of sprints to show (it'll show the last sprints it finds)
* `sprint_mapping`: Mapping of the sprints, can be used to use this job to retrieve multiple sprint burndowns (name => rapidViewId).

Example of `sprint_mapping`:

    sprint_mapping: 
        burndownProject1: 1
        burndownProject2: 23

### Option 1: `jira_burndown.yaml`

Create a `jira_burndown.yaml` file in the `/jobs` directory and configure it (example file in this repo).

### Option 2: `jira_burndown.rb`

Configure the `CONFIG` block in the ruby code.

## Dashboard configuration

Put the following in your dashingboard.erb file to show the status:

    <li data-row="1" data-col="1" data-sizex="1" data-sizey="2">
      <div data-id="burndownProject1" data-view="JiraBurdown"></div>
    </li>

Multiple burndowns can be added to a dashboard by repeating the snippet and changing the ```data-id```.

# License
Distributed under the [MIT license](https://github.com/vossim/dashing-jira-burndown/blob/master/LICENSE)
