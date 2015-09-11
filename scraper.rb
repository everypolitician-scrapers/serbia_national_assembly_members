# #!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'nokogiri'
require 'open-uri/cached'
require 'date'

OpenURI::Cache.cache_path = '.cache'

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end
end

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def get_social_details(social)
  details = {}
  social.each do |item|
    details[:facebook] = item.css('a/@href').to_s if item.text.to_s.index('Facebook account')
    details[:twitter] = item.css('a/@href').to_s if item.text.to_s.index('Twitter account')
    details[:website] = item.css('a/@href').to_s if item.text.to_s.index('Personal website')
    puts item.to_s.split('<a').first
  end

  return details
end

def scrape_list(url)
  noko = noko_for(url)
  noko.css('div.delegate_list tr td a/@href').each do |link|
    bio = URI.join(url, link.to_s)
    scrape_person(bio)
  end
end

def scrape_person(url)
  noko = noko_for(url)
  details = noko.css('div.optimize')

  id = url.to_s.gsub(/^.*\.(\d{3})\.\d{3}.*$/, '\1')

  name = details.css('h2').text.to_s.tidy
  dob = details.xpath('//h4[contains(.,"Year of Birth")]/following-sibling::p[not(position() > 1)]/text()').to_s.tidy
  dob = dob.gsub('.', '')

  start_date = details.xpath('//h4[contains(.,"Date of Verification of")]/following-sibling::p[not(position() > 1)]/text()').to_s.tidy
  start_date = Date.parse(start_date).to_s

  party = details.xpath('//h4[contains(.,"Political party")]/following-sibling::p[not(position() > 1)]/text()').to_s
  party = party.gsub(/\(.*$/, '').tidy
  party = '' if party == '-'

  faction = details.xpath('//h4[contains(.,"Parliamentary group")]/following-sibling::p/a[not(position() > 1)]/text()').to_s
  faction = faction.gsub('Read more ˃˃', '')
  faction = faction.gsub('Parliamentary Group', '').tidy
  faction = '' if faction == 'MPs not members of parliamentary groups'

  social = noko.xpath('//div[contains(@class,"single_member")]/following-sibling::div/ul/li')
  social_details = get_social_details(social)

  data = {
    id: id,
    name: name,
    faction: faction,
    party: party,
    start_date: start_date,
    birth_date: dob
  }

  data = data.merge(social_details)

  ScraperWiki.save_sqlite([:id], data)
end

scrape_list('http://www.parlament.gov.rs/national-assembly/composition/members-of-parliament/current-legislature.487.html')
