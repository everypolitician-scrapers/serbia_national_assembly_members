# frozen_string_literal: true
# #!/bin/env ruby
# encoding: utf-8

require 'pry'
require 'scraped'
require 'scraperwiki'

# require 'open-uri/cached'
# OpenURI::Cache.cache_path = '.cache'
require 'scraped_page_archive/open-uri'

class MembersPage < Scraped::HTML
  decorator Scraped::Response::Decorator::CleanUrls

  field :member_urls do
    noko.css('div.delegate_list tr td a/@href').map(&:text)
  end
end

class MemberPage < Scraped::HTML
  field :id do
    url.to_s.gsub(/^.*\.(\d+)\.\d+.*$/, '\1')
  end

  field :birth_date do
    details.xpath('//h4[contains(.,"Year of Birth")]/following-sibling::p[not(position() > 1)]/text()').to_s.delete('.').tidy
  end

  field :start_date do
    start = details.xpath('//h4[contains(.,"Date of Verification of")]/following-sibling::p[not(position() > 1)]/text()').to_s.tidy
    Date.parse(start).to_s
  end

  field :party do
    return '' if raw_party == '-'
    raw_party
  end

  field :faction do
    return '' if raw_faction == 'MPs not members of parliamentary groups'
    raw_faction
  end

  field :facebook do
    noko.css('.social-list a[href*=facebook]/href').text
  end

  field :twitter do
    noko.css('.social-list a[href*=twitter]/href').text
  end

  field :sort_name do
    details.css('h2').text.to_s.tidy
  end

  field :name do
    fixed_name[0]
  end

  field :honorific_prefix do
    fixed_name[1]
  end

  field :honorific_suffix do
    fixed_name[2]
  end

  field :source do
    url
  end

  private

  def details
    noko.css('div.optimize')
  end

  def raw_party
    details.xpath('//h4[contains(.,"Political party")]/following-sibling::p[not(position() > 1)]/text()').to_s.gsub(/\(.*$/, '').tidy
  end

  def raw_faction
    details.xpath('//h4[contains(.,"Parliamentary group")]/following-sibling::p[position() = 1]/a[not(position() > 1)]/text()')
           .to_s
           .gsub('Read more ˃˃', '')
           .gsub('Parliamentary Group', '')
           .tidy
  end

  # TODO: tidy this all up and move these to individual methods
  def fixed_name
    # we can't re-order the name parts because they don't seem to be
    # consistent on all the pages so lets not try. We can extract
    # Dr etc though so do that
    name = sort_name
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
  # puts data.reject { |k,v| v.to_s.empty? }.sort_by { |k,v| k }.to_h
  ScraperWiki.save_sqlite(%i[id term], data)
end

scrape_list('http://www.parlament.gov.rs/national-assembly/composition/members-of-parliament/current-legislature.487.html')
