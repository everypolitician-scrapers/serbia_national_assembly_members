# frozen_string_literal: true
# #!/bin/env ruby
# encoding: utf-8

require 'pry'
require 'scraped'
require 'scraperwiki'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'

require_rel 'lib'

class MembersPage < Scraped::HTML
  decorator Scraped::Response::Decorator::CleanUrls

  field :member_urls do
    noko.css('div.delegate_list tr td a/@href').map(&:text)
  end
end

def scraper(h)
  url, klass = h.to_a.first
  klass.new(response: Scraped::Request.new(url: url).response)
end

def scrape_list(url)
  scraper(url => MembersPage).member_urls.each do |href|
    scrape_person(href)
  end
end

def scrape_person(url)
  data = scraper(url => MemberPage).to_h.merge(term: 6)
  puts data.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h if ENV['MORPH_DEBUG']
  ScraperWiki.save_sqlite(%i[id term], data)
end

scrape_list('http://www.parlament.gov.rs/national-assembly/composition/members-of-parliament/current-legislature.487.html')
