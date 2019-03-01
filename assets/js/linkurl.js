function linkURL(text) {
  var re = RegExp("(\\b((https?|ftp|file):\/\/|www)[-A-Z0-9+&@#\/%?=~_|!:,.;]*[-A-Z0-9+&@#\/%=~_|]*)", "gi");
  document.documentElement.innerHTML = text.replace(re,"<a href='$1'>$1<\/a>");
}
