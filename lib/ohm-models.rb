#-------------------------------------------------------------------------------
# ohm/redis data models

require 'ohm'

Ohm.connect(:host => $gConfig[:redis][:host],
		:port => $gConfig[:redis][:port],
		:db => $gConfig[:redis][:db])
#Ohm.flush

$version = '0.2 redis/ohm'

#-------------------------------------------------------------------------------
# fic site data models

def initializeORM()
	# nothing to do
end

class Tag < Ohm::Model
	include TagMixin

	attribute :name	
	index :name
	
	def validate
		assert_present :name
		assert_unique :name
	end

	def self.findOrCreate(name)
		name.downcase!
		a = Tag.find(:name => name).first
		if a.nil?
			a = Tag.create(:name => name)
			a.save
		end
		a
	end

	def self.allSorted
		tagl = Tag.all()
		tagl.sort!
		tagl
	end
end

class Site < Ohm::Model
	attribute :title
	attribute :subtitle
	attribute :url
	attribute :description
	attribute :mtime
	attr_accessor :modified

	index :title

	def validate
		assert_present :title
		assert_present :url
	end
	
	def self.default
		# this tool is single-site but still has some multi-site cruft
		Site.all.first
	end

	def self.lastModified
		default = Site.default
		return default.modified if default != nil && default.modified != nil
		return $earliestDate
	end
	
	def modified=(tstamp)
		self.mtime = tstamp.to_s
	end
	
	def modified
		return nil if self.mtime.nil?
		return DateTime.parse(self.mtime)
	end
		
	def loadFromYaml(input)
		dirty = false
		if input.subtitle != self.subtitle && (self.subtitle != input.subtitle)
			dirty = true
			self.subtitle = input.subtitle 
		end
		if input.url
			input.url = input.url + '/' if input.url.slice(-1,1) != '/'
			input.url.strip!
			if self.url != input.url
				dirty != true
				self.url = input.url
			end
		end
		if input.description != nil && (self.description != input.description)
			self.description = input.description 
			dirty = true
		end
		if dirty && self.save
			puts "updating site #{self.title}"
			return true
		end
		return false
	end

	def self.findOrCreate(title)
		a = Site.find(:title => title).first
		if a.nil?
			a = Site.create(:title => title)
			a.save
		end
		a
	end
end


class Author < Ohm::Model
	attribute :name
	index :name
	attribute :login
	attribute :email
	attribute :url

	def validate
		assert_present :name
	end

	def loadFromYaml(input)
		dirty = false
		if input.name != nil && (self.name != input.name)
			self.name = input.name
			dirty = true
		end
		if input.login != nil && (self.login != input.login)
			self.login = input.login 
			dirty = true
		end
		if input.email != nil && (self.email != input.email)
			self.email = input.email 
			dirty = true
		end
		if dirty && self.save
			puts "updating author #{self.name}"
			return true
		end
		return false
	end

	def idtag
		return makeidtag(self.name)
	end

	def self.findOrCreate(name)
		a = Author.find(:name => name).first
		if a.nil?
			a = Author.create(:name => name)
			a.save
		end
		a
	end

	def toAtomPerson
		person = AtomPerson.new
		person.name = self.name
		person.email = self.email
		person.uri = self.url
		return person
	end
end

class Fandom < Ohm::Model
	attribute :idtag
	attribute :title
	attribute :default
	attribute :description
	
	set :stories, Story
	set :series, Series
	
	index :idtag
	index :default

	def validate
		assert_present :idtag
		assert_unique :idtag
		assert_present :title
	end

	def loadFromYaml(input)
		dirty = false
		if input.title != nil && (self.title != input.title)
			self.title = input.title
			dirty = true
		end
		if input.description != nil && (self.description != input.description)
			self.description = input.description
			dirty = true
		end
		if (input.default && (self.default == 'false' || self.default.nil?)) || (!input.default && (self.default == 'true'))
			self.default = input.default
			dirty = true
		end
		if dirty && self.save
			puts "updating fandom #{self.title}"
			return true
		end
		return false
	end

	def self.findOrCreate(idtag)
		idtag.downcase!
		a = Fandom.find(:idtag => idtag).first
		if a.nil?
			a = Fandom.create(:idtag => idtag)
			a.save
		end
		a
	end

	def standalone
		result = Story.find(:series => nil, :fandom => self)
		result.sort
		return result
	end
	
	def indexItems
		result = []
		self.series.each do |s|
			result << s
		end
		tmp = []
		self.stories.each do |s|
			tmp << s if (s.series == nil)
		end
		result = result | tmp
		result = result.sort_by {|item| [item.pairing_main.downcase, item.titleNoStopWords]}
		return result
	end

	def self.default
		result = Fandom.find(:default => true)
		result.first
	end
	
	def self.allSorted
		Fandom.all.sort_by(:idtag, :order => 'ASC ALPHA')
	end
end

class Pairing < Ohm::Model
	attribute :name
	collection :stories, Story
	
	index :name
	
	def validate
		assert_present :name
		assert_unique :name
	end

	def printable
		return makePairingPrintable(self.name)
	end

	def self.findOrCreate(name)
		name.downcase!
		result = Pairing.find(:name => name).first
		if result.nil?
			result = Pairing.create(:name => name)
			result.save
		end
		result
	end

	def self.allSorted
		Pairing.all.sort_by(:name, :order => 'ASC ALPHA')
	end
end

class Series < Ohm::Model
	include SeriesMixin
	attribute :idtag
	index :idtag
	attribute :title
	attribute :summary
	reference :banner, Banner
	
	set :authors, Author
	set :fandoms, Fandom
	list :stories, Story
	
	attribute :pairing_main
	attribute :modified
	attribute :published
	
	attr_accessor :bannerurl

	def validate
		assert_present :idtag
		assert_unique :idtag
	end

	def loadFromYaml(input)
		dirty = false
		if input.title != nil && (self.title != input.title)
			self.title = input.title
			dirty = true
		end
		if input.summary != nil && (self.summary != input.summary)
			self.summary = input.summary
			dirty = true
		end
		if input.published != nil && (self.published != input.published)
			self.published = input.published
			dirty = true
		end
		if input.pairing_main != nil && (self.pairing_main != input.pairing_main)
			self.pairing_main = input.pairing_main
			dirty = true
		end
		if input.bannerurl != nil
			b = Banner.findOrCreate(input.bannerurl)
			if b != self.banner
				self.banner = b
				dirty = true
			end
		end
		if dirty && self.save
			puts "updating series #{self.title}"
			return true
		end
		return false
	end

	def self.findOrCreate(idtag)
		idtag.downcase!
		a = Series.find(:idtag => idtag).first
		if a.nil?
			a = Series.create(:idtag => idtag)
			a.save
		end
		a
	end

	def storiesInOrder
		self.stories.sort_by(:series_order, :order => 'ASC')
	end

	def numeric_date
		latest = nil
		self.stories.each do |s|
			t = s.publicationDateTime
			latest = t if latest == nil or t > latest
		end
		return latest.strftime('%Y-%m-%d')
	end
end

# TODO using a global for this is hacky
$feedlist = nil

class Story < Ohm::Model
	include StoryMixin

	list :sections, Section
	set :authors, Author
	set :fandoms, Fandom

	set :pairings, Pairing
	attribute :pairing_main
	index :pairing

	set :tags, Tag	
	index :tag
	
	attribute :source
	attribute :title
	attribute :awards
	attribute :commentary
	attribute :disclaimer
	attribute :notes
	attribute :rating
	attribute :summary
	attribute :warnings
	attribute :wcount
	attr_accessor :wordcount
	
	attribute :mtime
	attribute :published

	reference :series, Series
	attribute :series_order
	
	attr_accessor :previousInSeries
	attr_accessor :nextInSeries
	
	reference :banner, Banner
	attr_accessor :bannerurl

	index :source
	index :title
	index :series
	
	def modified=(tstamp)
		self.mtime = tstamp.to_s
	end
	
	def modified
		return nil if self.mtime.nil?
		return DateTime.parse(self.mtime)
	end
	
	def self.standalone
		result = Story.find(:series => nil)
		result.sort
		return result
	end
	
	def self.totalCount
		# ohm doesn't seem to have a convenience for this
		Story.all.size
	end
	
	def self.allSorted
		coll = Story.all()
		stories = coll.map { |s| s }
		stories.sort!
		return stories
	end

	def self.taggedWith(tag)
		Story.find(tag: tag.name)
	end

	def self.findByPairing(pairing)
		Story.find(pairing: pairing.name)
	end

	def self.modifiedSince(lastmod)
		Story.all.find_all { |s| s.modified > lastmod }
	end
	
	def self.publishedBetween(start, stop)
		list = Story.db.zrangebyscore("story_ids_by_publication", 
				Time.parse(start.to_s).to_f,
				Time.parse(stop.to_s).to_f
				)
		return list.map { |id| Story[id] }
	end
	
	def self.fetchRecent(count)
		if $feedlist.nil?
			list = Story.db.zrevrange("story_ids_by_publication", 0, count - 1)
			$feedlist = list.map { |id| Story[id] }
		end
		$feedlist
	end
	
	def wouldBeInLatest()
		possibilities = Story.fetchRecent(10)
		fencepost = possibilities.last
		return self.published > fencepost.published
	end

	def publicationDateTime
		return DateTime.parse(self.published)
	end
	
	def wordcount=(count)
		self.wcount = count
	end
	
	def wordcount
		return 0 if self.wcount.nil?
		return Integer(self.wcount)
	end

	def altlink
		if self.sections != nil and self.sections.size > 0
			return self.sections[0].altlink
		end
		return nil
	end
	
	# note that pairings & tags are identical in behavior
	# they're merely separate namespaces TODO clean up
	def pairing
		self.pairings.map {|t| t.name}
	end

	def pairinglist=(tags)
		if tags.kind_of?([].class) 
			tagl = tags.uniq
		else
			tagl = tags.to_s.split(/\s*,\s*/).uniq
		end
		tagl.each do |n|
			t = Pairing.findOrCreate(n)
			self.pairings << t
		end
		self.save
	end

	def tag
		self.tags.map {|t| t.name}
	end
	
	def taglist=(tags)
		tags.to_s.split(/\s*,\s*/).uniq.each do |n|
			t = Tag.findOrCreate(n)
			self.tags << t
		end
		self.save
	end

	def tagsSorted
		self.tags.sort_by(:name, :order => 'ASC ALPHA')
	end

	def previousInSeries
		return nil if self.series == nil
		if @previousInSeries == nil
			stories = self.series.storiesInOrder
			stories.each do |s|
				break if s.series_order == self.series_order
				@previousInSeries = s
			end
		end
		return @previousInSeries
	end
	
	def nextInSeries
		return nil if self.series == nil
		if @nextInSeries == nil
			stories = self.series.storiesInOrder.reverse
			stories.each do |s|
				break if s.series_order == self.series_order
				@nextInSeries = s
			end
		end
		return @nextInSeries
	end

	def loadFromYaml(item, f, mtime, refresh)
		modtime = mtime.to_s
		if !refresh && (self.mtime != nil) && (modtime <= self.mtime)
			return false
		end

		if (self.published == nil)
			puts "adding '#{item['title']}'"
			if item['published'].nil?
				self.published = DateTime.now.to_s
			elsif item['published'].kind_of?(DateTime)
				self.published = item['published'].to_s
			elsif item['published'].kind_of?(Time)
				self.published = item['published'].to_s
			else
				self.published = item['published']
			end
		else
			puts "updating #{self.id}: '#{self.title}'"
		end
		self.modified = Time.now
		
		# update stored score of stories by publication date
		Story.db.zadd('story_ids_by_publication', Time.parse(self.published).to_f, self.id)
		
		if item['title'] == nil
			puts item['summary']
		end
		
		self.title = item['title'] if (self.title != item['title'])
		self.rating = item['rating'] if (self.rating != item['rating'])
		self.summary = rewriteLJLinks(item['summary']) if (self.summary != item['summary'])
		self.warnings = item['warnings'] if (self.warnings != item['warnings'])
		self.notes = rewriteLJLinks(item['notes']) if (self.notes != item['notes'])
		self.disclaimer = item['disclaimer'] if (self.disclaimer != item['disclaimer'])
		self.commentary = item['commentary'] if (self.commentary != item['commentary'])
		self.awards = item['awards'] if (self.awards != item['awards'])
		self.save
		
		if item['bannerurl'] != nil
			b = Banner.findOrCreate(item['bannerurl'])
			self.banner = b if b != self.banner
		end
		
		a = Author.findOrCreate(item['author'])
		self.authors << a
		
		self.pairing_main = item['pairing_main'] if item['pairing_main'] != nil && (self.pairing_main != item['pairing_main'])
		self.pairing_main = 'gen' if self.pairing_main == nil || self.pairing_main.length == 0
		self.pairing_main.downcase!

		if item['pairings']
			self.pairings.clear
			self.pairinglist = item['pairings'].join(', ')
		end
		a = Pairing.findOrCreate(self.pairing_main)
		self.pairings << a

		if item['tags']
			self.tags.clear
			self.taglist = item['tags'].join(', ')
		end
		
		if item['fandoms'] != nil
			item['fandoms'].each do |f|
				fandom = Fandom.findOrCreate(f)
				fandom.stories << self
				fandom.save
				self.fandoms << fandom
			end
		else
			default = Fandom.default()
			if default != nil && !self.fandoms.include?(default)
				default.stories << self
				default.save
				self.fandoms << default
			end
		end
		
		self.series_order = item['series-order'] if (item['series-order'] != self.series_order)
		if item['series-tag'] != nil
			series = Series.findOrCreate(item['series-tag'])
			self.series = series
			if !series.stories.member?(self)
				series.stories << self
			end
			
			self.fandoms.each do |f|
				f.series << series if !f.series.member?(f)
				series.fandoms << f
			end
			if series.pairing_main == nil
				series.pairing_main = self.pairing_main
			end
			series.save
		end
		
		if item['parts'] != nil
			i = 0
			item['parts'].each do |part|
				if i < self.sections.size
					items = self.sections
					segment = items[i]
					segment.title = part['title']
				else
					segment = Section.create(:title => part['title'])
					segment.save
					self.sections << segment
				end
				segment.summary = rewriteLJLinks(part['summary'])
				segment.content = rewriteLJLinks(part['content'])
				segment.altlink = part['altlink']
				if part['published']
					segment.published = DateTime.parse(part['published'])
				else
					segment.published = self.published
				end
				segment.modified = segment.modified
				segment.save
				i += 1
			end
		else
			if self.sections.size > 0
				segment = self.sections.first
				segment.title = self.title
				segment.published = self.published
				segment.modified = self.modified
			else
				segment = Section.create(:title => self.title, :published => self.published, :modified => self.modified)
				segment.save
				self.sections << segment
			end
			segment.summary = rewriteLJLinks(self.summary)
			segment.content = rewriteLJLinks(item['content'])
			segment.altlink = item['altlink']

			segment.save
		end
		
		self.wordcount = self.countWords

		if self.save
			return true
		else
			self.errors.each do |e|
				puts e
			end
		end
		return false
	end

	def self.findOrCreate(source, title)
		a = Story.find(:source => source, :title => title).first
		if a.nil?
			a = Story.create(:source => source, :title => title)
			a.save
		end
		a
	end
end

class Section < Ohm::Model
	include SectionMixin
	reference :story, Story
	
	attribute :title
	attribute :summary
	attribute :altlink
	attribute :content
	
	attribute :modified
	attribute :published
end

class Banner < Ohm::Model
	include BannerMixin

	attribute :url
	index :url
	attribute :width
	attribute :height
	attribute :alt
	attribute :link

	def loadFromYaml(input)
		dirty = false
		if input.url != self.url
			self.url = input.url
			dirty = true
		end
		if self.width.nil? || input.width != Integer(self.width)
			self.width = input.width
			dirty = true
		end
		if self.height.nil? || input.height != Integer(self.height)
			self.height = input.height
			dirty = true
		end
		if input.alt != self.alt
			self.alt = input.alt
			dirty = true
		end
		if input.link != self.link
			self.link = input.link
			dirty = true
		end

		if dirty && self.save
			puts "found banner #{self.alt}"
			return true
		end
		return false
	end

	def self.findOrCreate(url)
		b = Banner.find(:url => url).first
		b = Banner.create(:url => url) if b.nil?
		b.save
		b
	end
end

class StaticPage < Ohm::Model
	attribute :page
	index :page
	attribute :title
	attribute :content
	attribute :modified

	def loadFromYaml(input)
		dirty = false
		if input.page != nil && (self.page != input.page)
			self.page = input.page 
			dirty |= true
		end
		if input.title != nil && (self.title != input.title)
			self.title = input.title 
			dirty |= true
		end
		if input.content != nil && (self.content != input.content)
			self.content = input.content 
			dirty |= true
		end
		if dirty
			self.modified = DateTime.now
			puts "updating page #{self.title}"
			self.save
			return true
		end
		return false
	end

	def self.findOrCreate(page)
		a = StaticPage.find(:page => page).first
		if a.nil?
			a = StaticPage.create(:page => page)
			a.save
		end
		a
	end
	
	def self.modifiedSince(lastmod)
		StaticPage.all.find_all { |s| DateTime.parse(s.modified) > lastmod }
	end
end
