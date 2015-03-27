class Dashing.JiraBurndown extends Dashing.Widget
  @accessor 'more-info', Dashing.AnimatedValue

  ready: ->
    for childNode in @node.childNodes
      if (childNode.className == "graphContainer")
        @targetNode = childNode
    if !@chart && @data
      @chart = constructChart(@data, @targetNode)
      drawChart(@chart, @data)

  onData: (data) ->
    @data = data
    if !@chart && @targetNode
      @chart = constructChart(data, @targetNode)
    if @chart?
      drawChart(@chart, data)

  constructChart = (data, targetNode) ->
    numberOfSeries = data.series.length - 1
    xs = {}
    colors = {}
    for i in [0..numberOfSeries] by 1
      xs["y_"+i] = "x_"+i
      colors["y_"+i] = data.series[i].color
    container = $(@node).parent()
    width = (Dashing.widget_base_dimensions[0] * container.data("sizex")) + Dashing.widget_margins[0] * 2 * (container.data("sizex") - 1)
    height = (Dashing.widget_base_dimensions[1] * container.data("sizey"))
    @chart = c3.generate({
      bindto: targetNode,
      data: {
        xs: xs,
        columns: [],
        colors: colors
      },
      axis: {
        x: {
          show: false,
        },
        y: {
          show: true,
          min: 0,
          padding: {
            top: 0,
            bottom: 0
          },
          tick: {
            format: (e) ->
              Math.round( e / 3600 )
          }
        }
      },
      size: {
        width: width,
        height: height
      },
      legend: {
        show: false
      },
      tooltip: {
        show: false
      },
    });
    @chart
    
  drawChart = (chart, data) ->
    numberOfSeries = data.series.length - 1
    columns = []
    for i in [0..numberOfSeries] by 1
      x = ["x_"+i]
      y = ["y_"+i]
      for point in data.series[i].data
        x.push point.x
        y.push point.y
      columns.push x
      columns.push y
      
    chart.load({
      columns: columns
    })
