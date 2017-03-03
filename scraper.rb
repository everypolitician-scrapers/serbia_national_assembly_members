# frozen_string_literal: true
# #!/bin/env ruby
# encoding: utf-8

require 'date'
require 'scraped'
require 'scraperwiki'

# require 'open-uri/cached'
# OpenURI::Cache.cache_path = '.cache'
require 'scraped_page_archive/open-uri'

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def get_social_details(social)
  details = {}
  social.each do |item|
    details[:facebook] = item.css('a/@href').to_s if item.text.to_s.index('Facebook account')
    details[:twitter] = item.css('a/@href').to_s if item.text.to_s.index('Twitter account')
    details[:website] = item.css('a/@href').to_s if item.text.to_s.index('Personal website')
  end

  details
end

def fix_name(name)
  # we can't re-order the name parts because they don't seem to be
  # consistent on all the pages so lets not try. We can extract
  # Dr etc thoough so do that
  honorific_prefix = ''
  name.gsub(/(\s+(?:(?:Prof|Dr|Mrs|Dr\.med\.dent)\.?\s+)+)/i) do
    honorific_prefix = Regexp.last_match(1) or ''
    if honorific_prefix.size
      name = name.gsub(honorific_prefix, ' ')
      honorific_prefix = honorific_prefix.gsub('. ', ' ').tidy
      honorific_prefix = honorific_prefix.gsub('.$', '').tidy
      honorific_prefix = honorific_prefix.split(' ').map(&:capitalize) .join(' ')
    end
  end

  honorific_suffix = ''
  name.gsub(/(\s+(?:(?:PhD|MD|Prim|M\.?Sci)\.?\s+)+)/i) do
    honorific_suffix = Regexp.last_match(1) or ''
    if honorific_suffix.size
      name = name.gsub(honorific_suffix, ' ')
      honorific_suffix = honorific_suffix.gsub('. ', ' ').tidy
      honorific_suffix = honorific_suffix.gsub('.$', '').tidy
    end
  end

  name = name.gsub(' - ', ' ').tidy

  [name, honorific_prefix, honorific_suffix]
end

def scrape_list(url, term_map)
  noko = noko_for(url)
  noko.css('div.delegate_list tr td a/@href').each do |link|
    bio = URI.join(url, link.to_s)
    scrape_person(bio, term_map)
  end
end

def scrape_person(url, term_map)
  noko = noko_for(url)
  details = noko.css('div.optimize')

  id = url.to_s.gsub(/^.*\.(\d+)\.\d+.*$/, '\1')

  name = details.css('h2').text.to_s.tidy
  sort_name = name

  name, honorific_prefix, honorific_suffix = fix_name(name)

  dob = details.xpath('//h4[contains(.,"Year of Birth")]/following-sibling::p[not(position() > 1)]/text()').to_s.tidy
  dob = dob.delete('.')

  start_date = details.xpath('//h4[contains(.,"Date of Verification of")]/following-sibling::p[not(position() > 1)]/text()').to_s.tidy
  start_date = Date.parse(start_date).to_s

  party = details.xpath('//h4[contains(.,"Political party")]/following-sibling::p[not(position() > 1)]/text()').to_s
  party = party.gsub(/\(.*$/, '').tidy
  party = '' if party == '-'

  faction = details.xpath('//h4[contains(.,"Parliamentary group")]/following-sibling::p[position() = 1]/a[not(position() > 1)]/text()').to_s
  faction = faction.gsub('Read more ˃˃', '')
  faction = faction.gsub('Parliamentary Group', '').tidy
  faction = '' if faction == 'MPs not members of parliamentary groups'

  social = noko.xpath('//div[contains(@class,"single_member")]/following-sibling::div/ul/li')
  social_details = get_social_details(social)

  data = {
    id:               id,
    name:             name,
    sort_name:        sort_name,
    honorific_prefix: honorific_prefix,
    honorific_suffix: honorific_suffix,
    faction:          faction,
    party:            party,
    start_date:       start_date,
    birth_date:       dob,
    source:           url.to_s,
  }

  if !term_map[start_date].nil?
    data[:term] = term_map[start_date]
  else
    term_start = ''
    term_map.keys.sort.each do |start|
      term_start = start if start < start_date
    end
    data[:term] = term_map[term_start]
  end

  data = data.merge(social_details)
  # puts data.reject { |k,v| v.to_s.empty? }.sort_by { |k,v| k }.to_h

  if data[:term].nil?
    ScraperWiki.save_sqlite([:id], data)
  else
    ScraperWiki.save_sqlite(%i(id term), data)
  end
end

def create_terms(url)
  noko = noko_for(url)
  side_menu = noko.css('div.side_menu')
  link = side_menu.xpath('.//li/a[contains(.,"Legislature Archive")]')

  noko = noko_for(URI.join(url, link.first[:href]))
  side_menu = noko.css('div.side_menu')
  archives = side_menu.xpath('.//li/a[contains(.,"Legislature Archive")]/following-sibling::ul/li')

  date_to_term_map = {}
  count = 1
  archives.reverse.each do |term|
    name = term.text.tidy
    start = name.gsub(' legislature', '')
    start_date = Date.parse(start).to_s
    term = {
      name:       name,
      start_date: start_date,
      id:         count,
      source:     URI.join(url, term.css('a/@href').to_s).to_s,
    }
    date_to_term_map[start_date] = count
    ScraperWiki.save_sqlite([:id], term, 'terms')
    count += 1
  end
  unless date_to_term_map['2016-06-03'].nil?
    raise "the latest term has been archived, possibly there's been an election"
  end
  term = {
    name:       '3 June 2016 legislature',
    start_date: '2016-06-03',
    id:         count,
    source:     url,
  }
  date_to_term_map['2016-06-03'] = count
  ScraperWiki.save_sqlite([:id], term, 'terms')
  date_to_term_map
end

term_map = create_terms('http://www.parlament.gov.rs/national-assembly/composition/members-of-parliament/current-legislature.487.html')
scrape_list('http://www.parlament.gov.rs/national-assembly/composition/members-of-parliament/current-legislature.487.html', term_map)
