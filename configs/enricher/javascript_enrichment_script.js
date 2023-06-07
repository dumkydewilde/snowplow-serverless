function urlParamsToObject(urlParams) {
  let result = {};
  urlParams.split("&").forEach(function(part) {
    const item = part.split("=");
    result[item[0]] = decodeURIComponent(item[1]);
  });
  return result;
}

function process(event) {
    let contexts = []
    
    // Example of processing url params and returning a custom context
    if (event.getPage_urlquery()) {
      const urlParams = urlParamsToObject(event.getPage_urlquery());
      // Generate your custom context here
    } 

    return contexts;
  }

  