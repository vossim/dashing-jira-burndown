require 'net/http'
require 'open-uri'
require 'cgi'
require 'json'
require 'time'

yamlFile = "./jobs/jira_burndown.yaml"
if File.exist?(yamlFile)
  JIRA_CONFIG = YAML.load(File.new(yamlFile, "r").read)
else
  JIRA_CONFIG = {
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

  # private 
  def downloadJson(url)
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
        ! subEntry["statC"].nil? ||
        ! subEntry["column"].nil? 
        }.length > 0
        }.map{ |key, value|
          timeChanges = value.find_all { |valueEntry|
            ! valueEntry["statC"].nil? ||
            ! valueEntry["column"].nil?
          }
          [Time.at(key.to_f / 1000), timeChanges]
        }
      end

      def startEstimation
        jsonChangesByDateTime.find_all { |key, value|
          key < sprintStart && ! value[0]["statC"].nil?
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
                estimation + entry[1]["statC"]["newValue"].to_f
              }
            end

            def changesDuringSprint
              jsonChangesByDateTime.find_all { |key, value|
                key > sprintStart && key < sprintEnd 
                }.map { |key, value|
                  durationChange = value.reduce(0) {|res, story|
                    if ! story["statC"].nil? && story["column"].nil?
                      res - (story["statC"]["oldValue"].to_f - story["statC"]["newValue"].to_f)
                    elsif ! @json["changes"].find_all {|key, v|
                      v.find_all {|subEntry|
                        ! subEntry["statC"].nil? && subEntry["column"].nil? && subEntry["key"] == story["key"] 
                        }.length > 0
                        }.empty?
                        res - (@json["changes"].find_all {|key, v|
                          v.find_all {|subEntry|
                            ! subEntry["statC"].nil? && subEntry["column"].nil? && subEntry["key"] == story["key"] 
                            }.length > 0
                            }[0][1][0]["statC"]["newValue"].to_f)  
                      else
                       res.to_f  
                     end
                   }
                   [key, durationChange]
                   }.find_all { |key, value|
                    value != 0.0
                  }
                end

                def loggedTimeInSprint
                  jsonChangesByDateTime.find_all { |key, value|
                    key > sprintStart && key < sprintEnd
                    }.map { |key, value|
                      timeSpent = value.reduce(0) {|res, story|
                        if ! story["statC"].nil? && story["column"].nil?
                          res.to_f 
                        elsif ! @json["changes"].find_all {|key, v|
                          v.find_all {|subEntry|
                            ! subEntry["statC"].nil? && subEntry["column"].nil? && subEntry["key"] == story["key"] 
                            }.length > 0
                            }.empty?
                            res + (@json["changes"].find_all {|key, v|
                              v.find_all {|subEntry|
                                ! subEntry["statC"].nil? && subEntry["column"].nil? && subEntry["key"] == story["key"] 
                                }.length > 0
                                }[0][1][0]["statC"]["newValue"].to_f)  
                          else
                           res.to_f
                         end
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
                      {x: @rdr.sprintStart.to_f, y: @rdr.startEstimation},
                      {x: @rdr.sprintEnd.to_f, y: 0}
                    ]

                    lastEntry = Time.new.to_f
                    lastEntry = lastEntry > @rdr.sprintEnd.to_f ? @rdr.sprintEnd.to_f : lastEntry

                    realLine = [{x: @rdr.sprintStart.to_f, y: @rdr.startEstimation}]
                    realLine = @rdr.changesDuringSprint.reduce(realLine) { |res, entry|
                      beforeChange = res.last[:y]
                      afterChange = beforeChange + entry[1]
                      res << {x: entry[0].to_f, y: beforeChange} << {x: entry[0].to_f+1, y: afterChange}
                      } << {x: lastEntry, y: realLine[-1][:y]}

                      loggedLine = [{x: @rdr.sprintStart.to_f, y: 0}]
                      loggedLine = @rdr.loggedTimeInSprint.reduce(loggedLine) { |res, entry|
                        beforeChange = res.last[:y]
                        afterChange = beforeChange + entry[1]
                        res << {x: entry[0].to_f, y: beforeChange} << {x: entry[0].to_f+1, y: afterChange}
                        } << {x: lastEntry, y: loggedLine[-1][:y]}

                        lines = [
                          {name: "Target", color:"#959595", data: targetLine},
                          {name: "Logged", color: "#10cd10", data: loggedLine},
                          {name: "Real", color: "#cd1010", data: realLine}
                        ]
                      end
                    end

                    JIRA_BURNDOWNS = Hash.new()

                    JIRA_CONFIG[:sprint_mapping].each do |mappingName, rapidViewId|
                      sprintIndex = 0
                      SCHEDULER.every '10s', :first_in => 0 do
                        burndowns = JIRA_BURNDOWNS[mappingName]
                        if !burndowns.nil? && !burndowns.empty?
                          tempSprintIndex = sprintIndex
                          sprintIndex = (sprintIndex >= JIRA_CONFIG[:numberOfSprintsToShow]-1) ? 0 : sprintIndex + 1
                          send_event(mappingName, burndowns[tempSprintIndex])
                        end
                      end
                    end

                    JIRA_CONFIG[:sprint_mapping].each do |mappingName, rapidViewId|
                      SCHEDULER.every '10s', :first_in => 0 do
                        endNbr = JIRA_CONFIG[:numberOfSprintsToShow].to_i - 1
                        burndowns = [*0..endNbr].map do |sprintIndex|
                          downloader = SprintJsonDownloader.new(JIRA_CONFIG[:jira_url], JIRA_CONFIG[:username], JIRA_CONFIG[:password])
                          sprintOverview = SprintOverviewJsonReader.new(downloader.sprintOverview(rapidViewId), JIRA_CONFIG[:numberOfSprintsToShow]).getSprintOverview(sprintIndex)
                          sprintName = sprintOverview["name"]
                          sprintId = sprintOverview["id"]

                          reader = SprintJsonReader.new(downloader.sprintBurnDown(rapidViewId, sprintId))

                          lines = BurnDownBuilder.new(reader).buildBurnDown
                          {"more-info" => sprintName, series: lines}
                        end
                        JIRA_BURNDOWNS[mappingName] = burndowns
                      end
                    end