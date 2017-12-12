function lastUpdated() {
  var u = new Date(document.lastModified); var y = u.getFullYear(); var m = u.getMonth()+1; var d = u.getDate(); var H = u.getHours(); var M = u.getMinutes();
  document.getElementById('lastUpdated').innerHTML = y + '-' + (m<10 ? '0' : '') + m + '-' + (d<10 ? '0' : '') + d + ' ' + (H<10 ? '0' : '') + H + ':' + (M<10 ? '0' : '') + M;
}
window.onload = lastUpdated;
