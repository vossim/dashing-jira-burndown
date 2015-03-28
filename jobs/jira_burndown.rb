require 'net/http'
require 'open-uri'
require 'cgi'
require 'json'
require 'time'

yamlFile = "./jobs/jira_burndown.yaml"
if File.exist?(yamlFile)
  CONFIG = YAML.load(File.new(yamlFile, "r").read)
else
  CONFIG = {
    jira_url: "",
    username:  "",
    password: "",
    numberOfSprintsToShow: 1,
    sprint_mapping: {
      'myBurndown' => 0 
    }
  }
end

class SprintJsonDownloader
  def initialize(urlPrefix, username, password)
    @urlPrefix = urlPrefix
    @username = username
    @password = password
  end

  private def downloadJson(url)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    request = Net::HTTP::Get.new(uri.request_uri)
    if !@username.nil? && !@username.empty?
      request.basic_auth(@username, @password)
    end
    JSON.parse(http.request(request).body)
  end

  def sprintOverview(rapidViewId)
    downloadJson("#{@urlPrefix}/rest/greenhopper/1.0/sprintquery/#{rapidViewId}?includeFutureSprints=false")
  end

  def sprintBurnDown(rapidViewId, sprintId)
    downloadJson("#{@urlPrefix}/rest/greenhopper/1.0/rapid/charts/scopechangeburndownchart.json?rapidViewId=#{rapidViewId}&sprintId=#{sprintId}")
  end
end

class SprintOverviewJsonReader
  def initialize(json, numberOfSprintsToShow)
    @json = json
    @numberOfSprintsToShow = numberOfSprintsToShow
  end

  def getSprintOverview(sprintIndex)
    sprints = @json["sprints"][ -1 * @numberOfSprintsToShow, @numberOfSprintsToShow]
    sprints[sprintIndex]
  end
end

class SprintJsonReader
  def initialize(json)
    @json = json
  end

  def sprintStart
    Time.at(@json["startTime"] / 1000)
  end

  def sprintEnd
    Time.at(@json["endTime"] / 1000)
  end

  def jsonChangesByDateTime
    @json["changes"].find_all {|key, value|
      value.find_all {|subEntry|
        ! subEntry["timeC"].nil?
      }.length > 0
    }.map{ |key, value|
      timeChanges = value.find_all { |valueEntry|
        ! valueEntry["timeC"].nil?
      }
      [Time.at(key.to_i / 1000), timeChanges]
    }
  end

  def startEstimation
    jsonChangesByDateTime.find_all { |key, value|
      key < sprintStart
    }.flat_map { |key, value|
      value.map { |singleStory|
        [key, singleStory]
      }
    }.reverse_each.reduce([]) {|hash, entry|
      containsItem = hash.find{|tempEntry|
        tempEntry[1]["key"] == entry[1]["key"]
      }
      if containsItem.nil?
        hash.push([entry[0], entry[1]])
      else
        hash
      end
    }.reduce(0) {|estimation, entry|
      estimation + entry[1]["timeC"]["newEstimate"].to_i
    }
  end

  def changesDuringSprint
    jsonChangesByDateTime.find_all { |key, value|
      key > sprintStart && key < sprintEnd
    }.map { |key, value|
      durationChange = value.reduce(0) {|res, story|
        res - (story["timeC"]["oldEstimate"].to_i - story["timeC"]["newEstimate"].to_i)
      }
      [key, durationChange]
    }.find_all { |key, value|
      value != 0
    }
  end

  def loggedTimeInSprint
    jsonChangesByDateTime.find_all { |key, value|
      key > sprintStart && key < sprintEnd
    }.map { |key, value|
      timeSpent = value.reduce(0) {|res, story|
        res + story["timeC"]["timeSpent"].to_i
      }
      [key, timeSpent]
    }
  end
end

class BurnDownBuilder
  def initialize(sprintJsonReader)
    @rdr = sprintJsonReader
  end

  def buildBurnDown
    targetLine = [
      {x: @rdr.sprintStart.to_i, y: @rdr.startEstimation},
      {x: @rdr.sprintEnd.to_i, y: 0}
    ]
    realLine = [{x: @rdr.sprintStart.to_i, y: @rdr.startEstimation}]
    realLine = @rdr.changesDuringSprint.reduce(realLine) { |res, entry|
      beforeChange = res.last[:y]
      afterChange = beforeChange + entry[1]
      res << {x: entry[0].to_i, y: beforeChange} << {x: entry[0].to_i+1, y: afterChange}
    }
    loggedLine = [{x: @rdr.sprintStart.to_i, y: 0}]
    loggedLine = @rdr.loggedTimeInSprint.reduce(loggedLine) { |res, entry|
      beforeChange = res.last[:y]
      afterChange = beforeChange + entry[1]
      res << {x: entry[0].to_i, y: beforeChange} << {x: entry[0].to_i+1, y: afterChange}
    }

    lines = [
      {name: "Target", color:"#959595", data: targetLine},
      {name: "Logged", color: "#10cd10", data: loggedLine},
      {name: "Real", color: "#cd1010", data: realLine}
    ]
  end
end

CONFIG[:sprint_mapping].each do |mappingName, rapidViewId|
  sprintIndex = 0
  SCHEDULER.every '10s', :first_in => 0 do
    downloader = SprintJsonDownloader.new(CONFIG[:jira_url], CONFIG[:username], CONFIG[:password])
    sprintOverview = SprintOverviewJsonReader.new(downloader.sprintOverview(rapidViewId), CONFIG[:numberOfSprintsToShow]).getSprintOverview(sprintIndex)
    sprintName = sprintOverview["name"]
    sprintId = sprintOverview["id"]

    reader = SprintJsonReader.new(downloader.sprintBurnDown(rapidViewId, sprintId))

    lines = BurnDownBuilder.new(reader).buildBurnDown

    sprintIndex = (sprintIndex >= CONFIG[:numberOfSprintsToShow]-1) ? 0 : sprintIndex + 1

    send_event(mappingName, {"more-info" => sprintName, series: lines})
  end
end
