#IcyIRC - An in-development web-based IRC client
It can connect to irc, however it lacks many features and there are bugs.

###Running the development version
This application requires [node.js](https://nodejs.org/) to be installed.

1. Install the dependencies `npm install`
2. Install gulp globally `npm install -g gulp`
3. Start the gulp watcher task `gulp watch`
4. Run the server in development environment `./icyirc -d`

The client will be accessible at http://localhost:8002/

Or for better testing and not having to enter user details over and over again, use the URI scheme: `http://localhost:8002/[server.hostname[:<port>]/[?nick=<nickname>][#<channel>[,#<morechannel>]]]`