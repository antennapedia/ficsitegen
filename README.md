The ficsitegen tool is a Ruby script for building a fanfic archive site. Data is cached in a local database for faster html generation on successive runs of the tool. The site itself is entirely static. Some pages use jquery to sort listings or display tag data.

At the time of this writing, story and site data is read from yaml files. To get a new story into the system, you add a new yaml file to the input directory. Clearly a web app to add new data would be nicer than this, but I haven't felt the need to do anything beyond the command line yet.

The tool comes in several flavors depending on the database you'd like to use for storage: [sqlite](http://www.sqlite.org/) via [Datamapper](http://datamapper.org/), [Redis](http://redis.io/) via [ohm](http://ohm.keyvalue.org/), and [Mongodb](http://www.mongodb.org/) via [Mongoid](http://mongoid.org/).

## Prerequisites

The prerequisites are listed in the Gemfile. To install, use bundler:

	bundle install

Required gems for the core: bluecloth choice gepub haml htmlentities sass  
Datamapper version: datamapper dm-sqlite-adapter dm-ar-finders  
Redis version: redis nest ohm  
Mongo version: mongo bson_ext mongoid  

## Input

Examples of valid input are in the examples/ directory.

	site.yaml
	fandom.yaml
	series.yaml
	story.haml
	banner.yaml

## Configuration

Copy the `config.yml.sample` file to `config.yml` and edit. You can ignore the sections for storage methods you don't intend to use.

## Runtime options

Run without options to look for files modified since the last site update time.

Data storage options:

	--mongo                      Store data in mongodb via mongoid
	--redis                      Store data in redis via ohm
	--sqlite                     Store data in sqlite via datamapper [default]

Parsing and page generation:

	-p, --parse                      reparse all files
	-i, --index                      regenerate all index files
	-f, --feeds                      regenerate all feed files
	-e, --epub                       regenerate all epub files
	-g, --generate                   regenerate all html output files
	-y, --year=YEAR                  generate story listing for the given year
	-b, --bookmarks                  generate bookmarks file suitable for Pinboard import
	
	-h, --help                       Show this message
	-v, --version                    Show version
