#!/usr/bin/env ruby
#
# Mephisto2Tumblr
#
# Standalone Ruby script for connecting to a Mephisto database and publishing articles to Tumblr
# Usage: Fill in your database information and tumblr account information below and run ./m2t.rb
#
# If you have the RedCloth gem installed and Textile was used in Mephisto articles,
# Mephisto2Tumblr will parse it and spit out html to Tumblr since it only supports Markdown.
# 
# author: Steve Ehrenberg
# email : steve@dnite.org
# 
# Tested on: Ruby 1.8.7 with a Mephisto database 0.8.2

require 'rubygems'
require 'active_record'
require 'net/http'
require 'RedCloth' if Gem.available?('RedCloth')

# Mephisto2Tumblr will generate a file of rewrite rules for keeping your old links forwarding to 
# the new Tumblr blog. (Currently only supports Mephisto's /yyyy/mm/dd/slug URL format)
NEW_BLOG_URL = "http://new_tumblr_blog_url.com"
REWRITE_FILENAME = "rewrite_rules"

# Fill in your Tumblr email address and password here
TUMBLR_EMAIL =    "tumblr_email@domain.com"
TUMBLR_PASSWORD = "tumblrpassword"

# Database Information (Only tested with Postgresql, but I'd assume it works with MySQL too?)
DB_ADAPTER  = "postgresql"
DB_USERNAME = "database_user"
DB_PASSWORD = "databasepassword"
DB_DATABASE = "mephisto_production"
DB_HOST     = "localhost"

# How long should we pause after each request to Tumblr?
SLEEP_TIME = 2

#################################################################################################
# You shouldn't have to edit below here but feel free to if you need to tweak anything for 
# your specific Mephisto or database configuration
#################################################################################################

# Make the connection to the database
ActiveRecord::Base.establish_connection(:adapter =>"#{DB_ADAPTER}",:host =>"#{DB_HOST}",:database =>"#{DB_DATABASE}",:username =>"#{DB_USERNAME}",:password =>"#{DB_PASSWORD}")

# Establish classes for the ActiveRecord models
class Content < ActiveRecord::Base; end
class Tag < ActiveRecord::Base; end
class Tagging < ActiveRecord::Base; end
class Article < Content; end
class Comment < Content; end

# Use our classes and the tumblr api to push things to tumblr
puts "Attempting upload to Tumblr account: #{TUMBLR_EMAIL}"

# Tumblr API url
url = URI.parse('http://www.tumblr.com/api/write')

tumblr_ids = []

# Loop through all articles and publish to Tumblr
Article.all.each_with_index do |article, i|
  if article.published_at != nil
    
    # Find all the tags for an article
    taggings = Tagging.find_all_by_taggable_id(article.id)
    tag_names = []
    if taggings != nil
      taggings.each do |tagging|
        tag = Tag.find(tagging.tag_id)
        tag_names << tag.name
      end
      tags = tag_names.join(',')
    end
    
    # Setup strings for the body. If there is an excerpt, we have to combine it with the body.
    body_format = "html"
    body = (article.excerpt != "") ? "#{article.excerpt}<!-- more -->#{article.body}" : article.body 
    body_string = ""

    # Convert to HTML if we're using Textile
    if article.filter == "textile_filter" && Gem.available?('RedCloth')
      body_string = RedCloth.new(body).to_html
    elsif article.filter == "markdown_filter" || article.filter == "smartypants_filter"
      body_string = body
      body_format = "markdown"
    else
      body_string = body
    end
    
    print "Article #{i+1}: #{article.title} (Tags: #{tags}) ... "
    
    attr_map = {
      'email' => TUMBLR_EMAIL,
      'password' => TUMBLR_PASSWORD,
      'type' => 'regular',
      'generator' => 'Mephisto2Tumblr :: m2t.rb (Steve Ehrenberg)',
      'date' => article.published_at,
      'private' => 0,
      'tags' => tags,
      'format' => body_format,
      'slug' => article.permalink,
      'state' => 'published',
      'send-to-twitter' => 'no',
      'title' => article.title,
      'body' => body_string
    }
    
    # Now we can POST to Tumblr! We'll append the body of the responce here too just to make sure things are going well.
    res = Net::HTTP.post_form(url, attr_map)

    # Save the ID so we can create some rewrite rules for nginx later
    tumblr_ids << {
      :tumblr_id => res.body,
      :slug => article.permalink,
      :date => article.published_at
    }
    puts res.body
    
    # Sleep for a few seconds
    sleep(SLEEP_TIME)
    
  end
end

puts "Creating Rewrite file for NGINX: #{REWRITE_FILENAME}"
File.open(REWRITE_FILENAME, 'w') do |file|
  f.puts "location / {"
  tumblr_ids.each do |article|
    file.puts "    rewrite ^/#{article[:date].year}/#{article[:date].month}/#{article[:date].day}/#{article[:slug]}([/#/?//](.*))$ #{NEW_BLOG_URL}/#{article[:tumblr_id]}/#{article[:slug]} permanent;"
  end
  f.puts "}"
end
