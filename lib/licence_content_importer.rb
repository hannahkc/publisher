require 'csv'
require 'reverse_markdown'

class LicenceContentImporter
  
  LICENCE_CONTENT_FILENAME = 'unwritten-licences'
  attr_reader :imported, :existing, :failed
   
  def initialize(importing_user)
    @imported = []
    @existing = []
    @failed = []
    @api = GdsApi::Panopticon.new(Rails.env)
    @user = User.where(name: importing_user).first
    raise "User #{importing_user} not found, please provide the name of a valid user." unless @user
  end
  
  def self.run(method, importing_user=self.name)
    importer = LicenceContentImporter.new(importing_user)
    
    importer.csv_data(LICENCE_CONTENT_FILENAME).each do |row|
      importer.send(method, row)
    end
    
    puts importer.formatted_result(method == :import)
    
  end
  
  def report row
    identifier = row['OID']
    existing_editions = LicenceEdition.where(licence_identifier: identifier)

    if existing_editions.size > 0
      @existing << existing_editions
      @existing.flatten!
    else
      puts slug_for(row['NAME'])
      puts "---------------------------- marked down ---------------------------------"
      puts marked_down(row['LONGDESC'])
      puts "------------------------------- end --------------------------------------\n\n"

      @imported << { identifier: identifier, slug: slug_for(row['NAME']), description: marked_down(row['LONGDESC']) }
    end
  end
  
  def import row
    identifier = row['OID']
    existing_editions = LicenceEdition.where(licence_identifier: identifier)

    if existing_editions.size > 0
      @existing << existing_editions
      @existing.flatten!
    else
      title = CGI.unescapeHTML(row['NAME'])
      slug = slug_for(title)
      
      api_response = @api.create_artefact(slug: slug, kind: 'licence', state: 'draft',
        owning_app: 'publisher', name: title, rendering_app: "frontend", need_id: 1)
      
      if api_response && api_response.code == 201 # 'created' http response code
        artefact_id = api_response.to_hash['id']
                    
        puts "Created artefact in panopticon with id: #{artefact_id}, slug: #{slug}."
        
        edition = LicenceEdition.create title: title, panopticon_id: artefact_id, slug: slug, 
          licence_identifier: identifier, licence_overview: marked_down(row['LONGDESC'])
        
        if edition
          add_workflow(@user, edition)
          puts "Created LicenceEdition in publisher with panopticon_id: #{artefact_id}, licence_identifier: #{identifier}"       
          @imported << edition
        else
          @failed << identifier
          puts "Failed to import LicenceEdition to publisher. Identifier: #{identifier}."
        end
      else
        @failed << identifier
        puts "Failed to import LicenceEdition via panopticon API. Identifier: #{identifier}."
      end
    end
  end
  
  def add_workflow(user, edition)
    user.record_note(edition, "Imported #{Date.today.to_s(:db)}")
    type = Action.const_get(Action::CREATE.to_s.upcase)
    action = edition.new_action(user, type, {})
    edition.save!
  end
  
  def formatted_result(import=true)
    puts "--------------------------------------------------------------------------"
    puts "#{existing.size} LicenceEditions skipped."
    puts "#{imported.size} LicenceEditions#{(import ? '' : ' can be')} imported."
    puts "--------------------------------------------------------------------------"
  end
  
  def slug_for(title)
    title.parameterize.gsub("-amp-", "-and-")
  end
  
  def marked_down(str, unescape_html=false)
    str = CGI.unescapeHTML(str) if unescape_html
    ReverseMarkdown.parse(str)
  end
  
  def csv_data(name)
    CSV.read "#{Rails.root}/data/#{name}.csv", headers: true
  end
  
end
