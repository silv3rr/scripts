function lastUpdated(file) {
  var xhr = new XMLHttpRequest();
  xhr.open("HEAD", file, true);
  xhr.onload = function (e) {
    if (xhr.readyState === 4) {
      if (xhr.status === 200) {
	u = new Date(xhr.getResponseHeader("Last-Modified"));
	var y = u.getFullYear(); var m = u.getMonth()+1; var d = u.getDate(); var H = u.getHours(); var M = u.getMinutes();
	document.getElementById('lastUpdated').innerHTML = "updated " + y + '-' + (m<10 ? '0' : '') + m + '-' + (d<10 ? '0' : '') + d + ' ' + (H<10 ? '0' : '') + H + ':' + (M<10 ? '0' : '') + M;
      } else {
	document.getElementById('lastUpdated').innerHTML = "updated n/a";
      }
    }
  };
  xhr.onerror = function (e) {
    console.error(xhr.statusText);
  };
  xhr.send(null);
};
//window.onload = lastUpdated('README.md');
