# coding: utf-8
require 'sunflower'
require 'launchy'

require 'pp'


class InterwikiConflictSolver
	def initialize
		@sf = {}
		
		@all = []
		@groups = {}
		
		@linksfrom = {}
		@linksto = {}
		
		@summary_base = "semiautomatically fixing interwiki conflicts (trouble?: [[pl:User talk:#{user}]])"
		@summary = @summary_base
	end
	
	# Creates a Sunflower with customized settings and returns it; keeps a cache.
	def get_sf wiki
		if !@sf[wiki]
			@sf[wiki] = Sunflower.new wiki+'.wikipedia.org'
		
			@sf[wiki].warnings = false
			@sf[wiki].summary = @summary
		end
		
		return @sf[wiki]
	end
	
	def gather_from wiki, article
		start_pair = [wiki, article]
		if @all.include? start_pair
			puts "skipping #{start_pair.join ':'} - already reached"
			return
		end
		
		results = []
		results << [wiki, article]
		
		
		s = get_sf wiki
		res = s.API action:'query', prop:'langlinks', lllimit:500, titles:article
		
		iwlinks = (res['query']['pages'].first['langlinks']||[]).map{|hsh| [ hsh['lang'], hsh['*'] ] }
		
		results += iwlinks
		queue = iwlinks.dup
		
		i = 1
		while now = queue.shift
			wiki, article = *now
			puts "#{wiki.ljust 8} #{queue.length} left"
			
			s = get_sf wiki
			res = s.API action:'query', prop:'langlinks', lllimit:500, titles:article
			iwlinks = (res['query']['pages'].first['langlinks'] || []).map{|hsh| [ hsh['lang'], hsh['*'] ] }
			
			iwlinks.each do |pair|
				@linksto[pair] ||= []
				@linksto[pair] << now
			end
			
			@linksfrom[now] ||= []
			@linksfrom[now] += iwlinks
			
			iwlinks.each do |pair|
				unless results.include? pair
					results << pair
					queue << pair
				end
			end
		end
		
		results = (follow_redirects results).uniq
		@all += results
		@all.uniq!
		@all.sort!
		
		results.each do |pair|
			if @groups[pair]
				@groups[pair] += ', '+(start_pair.join ':')
			else
				@groups[pair] = "reached from #{start_pair.join ':'}"
			end
		end
	end
	
	def gather_from_many pairs
		pairs.each{|pair| gather_from *pair}
	end
	
	def follow_redirects pairs
		pairs.map do |wiki, title|
			s = get_sf wiki
			res = s.API action:'query', titles:title, redirects:true
			if res['query']['redirects']
				[wiki, res['query']['redirects'][0]['to'] ]
			else
				[wiki, title]
			end
		end
	end
	
	
	
	def pretty_iw pairs
		pairs.map{|a| "[[#{a.join ':'}]]"}
	end
	
	# Log in all wikis. Returns true on success.
	def login_all user, pass
		puts 'logging in... (wait)'
		@sf.each_with_index do |kv, i|
			wiki, s = *kv
			
			s.login CGI.escape(user), CGI.escape(pass)
			print "#{i+1}/#{@sf.length}\r"
		end
	end
	
	def busy_loop
		puts "#{@all.length} articles in #{@sf.length} languages."
		puts ''

		puts 'log in to edit (leave empty to just preview):'
		print 'username: '; user = gets.strip
		print 'password: '; pass = gets.strip

		do_log_in = (user!='' and pass!='')
		@logged_in = login_all(user, pass) if do_log_in
		pass = nil
		puts(@logged_in ? 'logged in.' : 'preview-only mode.')
		
		while true
			print '> '
			read = gets.strip
			
			case read
			when ''
				# pass
				
			when 'help'
				puts 'commands:'
				puts [
					'help',
					'show',
					'showg',
					'summary <text>',
					'linksto <lang> <title>',
					'linksfrom <lang> <title>',
					'start <lang> <title>',
					'start <lang>',
					'rename <group> <group>',
					'move <lang> <regex> <group>',
					'move * <regex> <group>',
					'gather <lang> <title>',
					'commit',
					'exit',
				]
				
			when 'exit'
				break
				
			when 'show'
				@all.each do |pair|
					puts "#{pair.join(':').encode('cp852', undef: :replace).ljust 40, '.'}#{@groups[pair].encode('cp852', undef: :replace)}"
				end
				
			when 'showg'
				lists_per_group = {} # {groupname => [pairs]}
				@groups.each_pair do |pair, group|
					lists_per_group[group] ||= []
					lists_per_group[group] << pair
				end
				lists_per_group.each_value{|gr| gr.sort!}
				
				lists_per_group.each_pair do |group, pairs|
					puts ">>> #{group}"
					puts pretty_iw pairs
					puts ''
				end
				
			when /\Asummary (.+)\Z/
				@summary = [@summary_base, $1].join ' - '
				@sf.each_with_index do |kv, i|
					wiki, s = *kv
					s.summary = @summary
				end
				
			when /\Alinksfrom ([a-z-]+) (.+)\Z/
				wiki, title = $1, $2
				puts pretty_iw @linksfrom[ [wiki, title] ]
				
			when /\Alinksto ([a-z-]+) (.+)\Z/
				wiki, title = $1, $2
				puts pretty_iw @linksto[ [wiki, title] ]
			
			when /\Astart \*\Z/
				@all.each{|wiki, title| Launchy.open "http://#{wiki}.wikipedia.org/w/index.php?title=#{CGI.escape title}" }
				
			when /\Astart ([a-z-]+) (.+)\Z/, /\Astart ([a-z-]+)\Z/
				wiki, title = $1, $2
				pairs = title ? [wiki, title] : @all.select{|pair| pair[0]==wiki}
				
				pairs.each{|wiki, title| Launchy.open "http://#{wiki}.wikipedia.org/w/index.php?title=#{CGI.escape title}" }
				
			when /\Amove \* (.+?) ([a-z0-9]+)\Z/, /\Amove \* ()([a-z0-9]+)\Z/
				name_reg, target_group = /#{$1}/i, $2
				
				got = @all.select{|pair| name_reg=~pair[1]}
				got.each do |pair|
					@groups[pair] = target_group
				end
			
			when /\Amove ([a-z-]+) (.+?) ([a-z0-9]+)\Z/, /\Amove ([a-z-]+) ()([a-z0-9]+)\Z/
				wiki, name_reg, target_group = $1, /#{$2}/i, $3
				
				got = @all.select{|pair| pair[0]==wiki and name_reg=~pair[1]}
				if got.length==1
					pair = got[0]
					@groups[pair] = target_group
				elsif got.empty?
					puts 'uh oh. no matches!'
				else
					puts 'uh oh. multiple matches!'
				end
			
			when /\Agather ([a-z-]+) (.+)\Z/
				wiki, title = $1, $2
				gather_from wiki, title
				
			when /\Arename ([a-z0-9]+) ([a-z0-9]+)\Z/, /\Amerge ([a-z0-9]+) ([a-z0-9]+)\Z/
				from, to = $1, $2
				@groups.each_key do |k|
					@groups[k] = to if @groups[k]==from
				end
				
			when 'commit'
				if @logged_in
					puts "are you sure you know what you're doing? (yes/no)"
					if gets.strip.downcase=='yes'
						lists_per_group = {} # {groupname => [pairs]}
						@groups.each_pair do |pair, group|
							lists_per_group[group] ||= []
							lists_per_group[group] << pair
						end
						lists_per_group.each_value{|gr| gr.sort!}
						
						# pp lists_per_group
						# gets
						
						clear_iw_regex = /\[\[(?:#{@all.map{|a| a[0]}.uniq.join '|'}):.+?\]\](?:\r?\n)?/
						# p clear_iw_regex
						# gets
						
						lists_per_group.each_pair do |group, pairs|
							next if group=='donttouch' or group=~/\Areached from/
							puts group+'...'
							
							pairs.each do |pair|
								wiki, title = *pair
								page = Page.new title, wiki
								
								if page.text.scan(clear_iw_regex).sort == pretty_iw(pairs-[pair]).sort
									puts "#{(pretty_iw [pair])[0]} - no changes needed"
								else
									page.text = (page.text.gsub clear_iw_regex, '').strip
									page.text += "\n\n" + pretty_iw(pairs-[pair]).join("\n") unless group=='clear'
									
									res = page.save
									puts "#{(pretty_iw [pair])[0]} #{res['edit']['result']=="Success" ? 'saved' : 'failure!!!'}"
									
									gets
								end
							end
						end
						
						puts 'done!'
						
					else
						puts 'aborted.'
					end
				else
					puts 'not logged in!'
				end
				
			else
				puts "d'oh? incorrect command."
			end
		end
	end
end





start_pairs = ARGV.map{|title| title.split(':', 2) }
# start_pairs = [
	# ['pl', 'Edgar'],
	# ['en', 'Edgar (disambiguation)'],
	# ['es', 'Edgar (desambiguación)'],
# ]

iw = InterwikiConflictSolver.new
iw.gather_from_many start_pairs
ARGV.pop until ARGV.empty?

iw.busy_loop



