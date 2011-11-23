The ficsitegen tool is a Ruby script for building a fanfic archive site. Data is cached in a local database for faster html generation on successive runs of the tool. The generated site itself is entirely static. Some pages use jquery to sort listings or display tag data.

At the time of this writing, story and site data is read from [yaml](http://www.yaml.org/) files. To add a new story into the system, you add a new yaml file to the input directory. Clearly a web app to add new data would be nicer than this, but I haven't felt the need to do anything beyond the command line yet.

The tool comes in several flavors depending on the database you'd like to use for storage: [sqlite](http://www.sqlite.org/) via [Datamapper](http://datamapper.org/), [Redis](http://redis.io/) via [ohm](http://ohm.keyvalue.org/), and [Mongodb](http://www.mongodb.org/) via [Mongoid](http://mongoid.org/).

Site features:

* per-fandom index pages
* sortable listing for all stories
* clouds for tags & pairings
* atom/rss feed for the 10 most recent stories
* epub versions of all content
* automatic linking between stories in series

I use this tool to generate [antennapedia.com](http://antennapedia.com). 

## Sample usage and ouput

Edit input files, then run the script.

	ficsitegen> ./sitegen.rb
	Using sqlite for storage.
	Site last updated Tue, 22 Nov 2011 14:31PM
	
	updating 26: 'Arms and the Man'
	1 story was updated.
	
	Generating pages for Arms and the Man...
	Generating newest-stories page...
	Generating atom feeds...
	Generating btvs index...
	Generating index page...
		sortable index...
		pairings page...
		tags page...
	Looking for changed static files...
	Done; 13 seconds elapsed.
	
You can then use rsync to push the changed files to your web host.

## Prerequisites

The prerequisites are listed in the Gemfile. To install, use bundler:

	bundle install
	
The gems are grouped by storage method, so if you have no intention of using the nosql databases, you can install only the gems you want. For instance, to skip installing the mongo gems:

	bundle install --without mongo

## Input

Examples of valid yaml input are in the examples/ directory.

site.yaml
: The site title & url.

fandom.yaml
: Information about a specific fandom featured.

series.yaml
: Meta-information about a story series.

story.haml
: Hash describing a story.

banner.yaml
: A story or series banner.

page.yaml
: A static non-fic page, such as a credits page.

static/
: Folder containing any static assets required by the site, such as images. These are copied intact to the output directory, with directory structure intact.

## Configuration

Copy the `config.yml.sample` file to `config.yml` and edit. You can ignore the sections for storage methods you don't intend to use.

## Runtime options

Run without options to look for files modified since the last site update time. The tool will regenerate html for any data changed. It will also rebuild anything that depends on template files modified since the last run.

Data storage options:

	--mongo                Store data in mongodb via mongoid
	--redis                Store data in redis via ohm
	--sqlite               Store data in sqlite via datamapper [default]

Parsing and page generation:

	-p, --parse            reparse all files
	-i, --index            regenerate all index files
	-f, --feeds            regenerate all feed files
	-e, --epub             regenerate all epub files
	-g, --generate         regenerate all html output files
	-y, --year=YEAR        generate story listing for the given year
	-b, --bookmarks        generate bookmarks file suitable for Pinboard import
	
	-h, --help             Show this message
	-v, --version          Show version
