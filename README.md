# webtriggers
Monitor web pages for changes and trigger actions

# Dependencies

 - chromium-browser for fetching web pages
 - [pup](https://github.com/ericchiang/pup) for extracting elements from HTML
 - [spd-say](https://manpages.ubuntu.com/manpages/trusty/man1/spd-say.1.html) for TTS

# Usage

1. Create a configuration file at `~/.webtriggers` with the following format:

```
- url: https://www.isitfriday.info/
  querySelector: h2#answer
  condition: 
  interval: 1h # Check every hour
  message: "Is it friday? {{value}}."
  handler: say,notify
  # empty newline is important

```

2. Start the webtriggers script

```
webtriggers.sh
```

It will read the configuration file, fetch the web page, extract the element using the query selector, evaluate the condition, and trigger the handler if the condition is met.


