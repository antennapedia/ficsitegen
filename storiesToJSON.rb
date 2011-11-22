#!/usr/bin/env ruby

# Convert all story yaml files in the input directory to json.
# Stories are pulled out into individual files when necessary.

require 'fileutils'
require 'json'
require 'pathname'
require 'yaml'

$output = 'json'
$input = 'input'

def main()
	FileUtils.mkdir_p(Pathname.new($output))

	Dir[$input + "/*.yaml"].each do |f|
		begin
			fp = File.open(f)
			outname = f.gsub('.yaml', '')
			outname.gsub!($input, $output)
			count = 1
			YAML.load_documents(fp) do |ydoc|
				if ydoc.kind_of?({}.class)
					ydoc['published'] = DateTime.parse(ydoc['published']).to_s
					if count > 1
						outp =  File.new("#{outname}_#{count}.json", 'w')
					else
						outp =  File.new("#{outname}.json", 'w')
					end
					outp.puts JSON.pretty_generate(ydoc)
					outp.close
					count += 1
				end
			end
			fp.close
		rescue StandardError => err
			puts "Error reading #{f}"
			puts err.inspect
			next
		end
	end
end

if $0 == __FILE__
	main()
end