window.kpis = {};

window.kpis.dateTimeLabelFormats = {
  millisecond: '%H:%M:%S.%L',
  second: '%H:%M:%S',
  minute: '%H:%M',
  hour: '%H:%M',
  day: '%e. %b',
  week: '%e. %b',
  month: '%b \'%y',
  year: '%Y'
};

window.kpis.config = {
  credits: {
    enabled: false
  },
  title: {
    text: 'title'
  },
  xAxis: {
    type: 'datetime',
    dateTimeLabelFormats: window.kpis.dateTimeLabelFormats
  },
  yAxis: {
    title: null
  },
  tooltip: {
    valueSuffix: ''
  },
  series: null
};

window.kpis.config_stacked = {
  credits: {
    enabled: false
  },
  chart: {
    type: 'area'
  },
  title: {
    text: 'title'
  },
  xAxis: {
    type: 'datetime',
    dateTimeLabelFormats: window.kpis.dateTimeLabelFormats
  },
  yAxis: {
    title: null
  },
  tooltip: {
    valueSuffix: ''
  },
  plotOptions: {
    area: {
      stacking: 'normal'
    }
  },
  series: null
};
