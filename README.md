#IcyIRC - An in-development web-based IRC client
###NOTICE! In the current stage this is **NOT** functional as an IRC client!

###Running the development version
1. Install the dependencies `npm install`
2. Install gulp globally `npm install -g gulp`
3. Start the gulp watcher task `gulp watch`
4. Run the server in development env `./icyirc -d`
The client will be accessible at http://localhost:8002/

###Running tests in-client
Current test commands are the following:

`testjoin` - Joins an example channel

`testjoin-more` - Joins another example channel

`test1` - An example JOIN event

`pmme` - An example PRIVMSG event to the client

You can also change your nickname by clicking on your nickname next to input field.