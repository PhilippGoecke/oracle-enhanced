require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe "OracleEnhancedAdapter schema definition" do
  include SchemaSpecHelper

  before(:all) do
    ActiveRecord::Base.establish_connection(CONNECTION_PARAMS)
    @conn = ActiveRecord::Base.connection
  end

  describe "table and sequence creation with non-default primary key" do

    before(:all) do
      schema_define do
        create_table :keyboards, :force => true, :id  => false do |t|
          t.primary_key :key_number
          t.string      :name
        end
        create_table :id_keyboards, :force => true do |t|
          t.string      :name
        end
      end
      class ::Keyboard < ActiveRecord::Base
        set_primary_key :key_number
      end
      class ::IdKeyboard < ActiveRecord::Base
      end
    end

    after(:all) do
      schema_define do
        drop_table :keyboards
        drop_table :id_keyboards
      end
      Object.send(:remove_const, "Keyboard")
      Object.send(:remove_const, "IdKeyboard")
    end

    it "should create sequence for non-default primary key" do
      ActiveRecord::Base.connection.next_sequence_value(Keyboard.sequence_name).should_not be_nil
    end

    it "should create sequence for default primary key" do
      ActiveRecord::Base.connection.next_sequence_value(IdKeyboard.sequence_name).should_not be_nil
    end
  end

  describe "sequence creation parameters" do

    def create_test_employees_table(sequence_start_value = nil)
      schema_define do
        create_table :test_employees, sequence_start_value ? {:sequence_start_value => sequence_start_value} : {} do |t|
          t.string      :first_name
          t.string      :last_name
        end
      end
    end

    def save_default_sequence_start_value
      @saved_sequence_start_value = ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value
    end

    def restore_default_sequence_start_value
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value = @saved_sequence_start_value
    end

    before(:each) do
      save_default_sequence_start_value
    end
    after(:each) do
      restore_default_sequence_start_value
      schema_define do
        drop_table :test_employees
      end
      Object.send(:remove_const, "TestEmployee")
    end

    it "should use default sequence start value 10000" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value.should == 10000

      create_test_employees_table
      class ::TestEmployee < ActiveRecord::Base; end

      employee = TestEmployee.create!
      employee.id.should == 10000
    end

    it "should use specified default sequence start value" do
      ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter.default_sequence_start_value = 1

      create_test_employees_table
      class ::TestEmployee < ActiveRecord::Base; end

      employee = TestEmployee.create!
      employee.id.should == 1
    end

    it "should use sequence start value from table definition" do
      create_test_employees_table(10)
      class ::TestEmployee < ActiveRecord::Base; end

      employee = TestEmployee.create!
      employee.id.should == 10
    end

    it "should use sequence start value and other options from table definition" do
      create_test_employees_table("100 NOCACHE INCREMENT BY 10")
      class ::TestEmployee < ActiveRecord::Base; end

      employee = TestEmployee.create!
      employee.id.should == 100
      employee = TestEmployee.create!
      employee.id.should == 110
    end

  end

  describe "create table with primary key trigger" do
    def create_table_with_trigger(options = {})
      options.merge! :primary_key_trigger => true, :force => true
      schema_define do
        create_table :test_employees, options do |t|
          t.string      :first_name
          t.string      :last_name
        end
      end
    end

    def create_table_and_separately_trigger(options = {})
      options.merge! :force => true
      schema_define do
        create_table :test_employees, options do |t|
          t.string      :first_name
          t.string      :last_name
        end
        add_primary_key_trigger :test_employees, options
      end
    end

    after(:all) do
      seq_name = @sequence_name
      schema_define do
        drop_table :test_employees, (seq_name ? {:sequence_name => seq_name} : {})
      end
      Object.send(:remove_const, "TestEmployee")
      @conn.clear_prefetch_primary_key
    end

    describe "with default primary key" do
      before(:all) do
        create_table_with_trigger
        class ::TestEmployee < ActiveRecord::Base
        end
      end

      it "should populate primary key using trigger" do
        lambda do
          @conn.execute "INSERT INTO test_employees (first_name) VALUES ('Raimonds')"
        end.should_not raise_error
      end

      it "should return new key value using connection insert method" do
        insert_id = @conn.insert("INSERT INTO test_employees (first_name) VALUES ('Raimonds')", nil, "id")
        @conn.select_value("SELECT test_employees_seq.currval FROM dual").should == insert_id
      end
      
      it "should create new record for model" do
        e = TestEmployee.create!(:first_name => 'Raimonds')
        @conn.select_value("SELECT test_employees_seq.currval FROM dual").should == e.id
      end
    end

    describe "with separate creation of primary key trigger" do
      before(:all) do
        create_table_and_separately_trigger
        class ::TestEmployee < ActiveRecord::Base
        end
      end

      it "should populate primary key using trigger" do
        lambda do
          @conn.execute "INSERT INTO test_employees (first_name) VALUES ('Raimonds')"
        end.should_not raise_error
      end

      it "should return new key value using connection insert method" do
        insert_id = @conn.insert("INSERT INTO test_employees (first_name) VALUES ('Raimonds')", nil, "id")
        @conn.select_value("SELECT test_employees_seq.currval FROM dual").should == insert_id
      end
      
      it "should create new record for model" do
        e = TestEmployee.create!(:first_name => 'Raimonds')
        @conn.select_value("SELECT test_employees_seq.currval FROM dual").should == e.id
      end
    end

    describe "with non-default primary key and non-default sequence name" do
      before(:all) do
        @primary_key = "employee_id"
        @sequence_name = "test_employees_s"
        create_table_with_trigger(:primary_key => @primary_key, :sequence_name => @sequence_name)
        class ::TestEmployee < ActiveRecord::Base
          set_primary_key "employee_id"
        end
      end

      it "should populate primary key using trigger" do
        lambda do
          @conn.execute "INSERT INTO test_employees (first_name) VALUES ('Raimonds')"
        end.should_not raise_error
      end

      it "should return new key value using connection insert method" do
        insert_id = @conn.insert("INSERT INTO test_employees (first_name) VALUES ('Raimonds')", nil, @primary_key)
        @conn.select_value("SELECT #{@sequence_name}.currval FROM dual").should == insert_id
      end

      it "should create new record for model with autogenerated sequence option" do
        e = TestEmployee.create!(:first_name => 'Raimonds')
        @conn.select_value("SELECT #{@sequence_name}.currval FROM dual").should == e.id
      end
    end

    describe "with non-default sequence name and non-default trigger name" do
      before(:all) do
        @sequence_name = "test_employees_s"
        create_table_with_trigger(:sequence_name => @sequence_name, :trigger_name => "test_employees_t1")
        class ::TestEmployee < ActiveRecord::Base
          set_sequence_name :autogenerated
        end
      end

      it "should populate primary key using trigger" do
        lambda do
          @conn.execute "INSERT INTO test_employees (first_name) VALUES ('Raimonds')"
        end.should_not raise_error
      end

      it "should return new key value using connection insert method" do
        insert_id = @conn.insert("INSERT INTO test_employees (first_name) VALUES ('Raimonds')", nil, "id")
        @conn.select_value("SELECT #{@sequence_name}.currval FROM dual").should == insert_id
      end

      it "should create new record for model with autogenerated sequence option" do
        e = TestEmployee.create!(:first_name => 'Raimonds')
        @conn.select_value("SELECT #{@sequence_name}.currval FROM dual").should == e.id
      end
    end

  end

  describe "table and column comments" do

    def create_test_employees_table(table_comment=nil, column_comments={})
      schema_define do
        create_table :test_employees, :comment => table_comment do |t|
          t.string      :first_name, :comment => column_comments[:first_name]
          t.string      :last_name, :comment => column_comments[:last_name]
        end
      end
    end

    after(:each) do
      schema_define do
        drop_table :test_employees
      end
      Object.send(:remove_const, "TestEmployee")
      ActiveRecord::Base.table_name_prefix = nil
    end

    it "should create table with table comment" do
      table_comment = "Test Employees"
      create_test_employees_table(table_comment)
      class ::TestEmployee < ActiveRecord::Base; end

      @conn.table_comment("test_employees").should == table_comment
      TestEmployee.table_comment.should == table_comment
    end

    it "should create table with columns comment" do
      column_comments = {:first_name => "Given Name", :last_name => "Surname"}
      create_test_employees_table(nil, column_comments)
      class ::TestEmployee < ActiveRecord::Base; end

      [:first_name, :last_name].each do |attr|
        @conn.column_comment("test_employees", attr.to_s).should == column_comments[attr]
      end
      [:first_name, :last_name].each do |attr|
        TestEmployee.columns_hash[attr.to_s].comment.should == column_comments[attr]
      end
    end

    it "should create table with table and columns comment and custom table name prefix" do
      ActiveRecord::Base.table_name_prefix = "xxx_"
      table_comment = "Test Employees"
      column_comments = {:first_name => "Given Name", :last_name => "Surname"}
      create_test_employees_table(table_comment, column_comments)
      class ::TestEmployee < ActiveRecord::Base; end

      @conn.table_comment(TestEmployee.table_name).should == table_comment
      TestEmployee.table_comment.should == table_comment
      [:first_name, :last_name].each do |attr|
        @conn.column_comment(TestEmployee.table_name, attr.to_s).should == column_comments[attr]
      end
      [:first_name, :last_name].each do |attr|
        TestEmployee.columns_hash[attr.to_s].comment.should == column_comments[attr]
      end
    end

  end

  describe "create triggers" do

    before(:all) do
      schema_define do
        create_table  :test_employees do |t|
          t.string    :first_name
          t.string    :last_name
        end
      end
      class ::TestEmployee < ActiveRecord::Base; end
    end

    after(:all) do
      schema_define do
        drop_table :test_employees
      end
      Object.send(:remove_const, "TestEmployee")
    end

    it "should create table trigger with :new reference" do
      lambda do
        @conn.execute <<-SQL
        CREATE OR REPLACE TRIGGER test_employees_pkt
        BEFORE INSERT ON test_employees FOR EACH ROW
        BEGIN
          IF inserting THEN
            IF :new.id IS NULL THEN
              SELECT test_employees_seq.NEXTVAL INTO :new.id FROM dual;
            END IF;
          END IF;
        END;
        SQL
      end.should_not raise_error
    end
  end

  describe "add index" do

    it "should return default index name if it is not larger than 30 characters" do
      @conn.index_name("employees", :column => "first_name").should == "index_employees_on_first_name"
    end

    it "should return shortened index name by removing 'index', 'on' and 'and' keywords" do
      @conn.index_name("employees", :column => ["first_name", "email"]).should == "i_employees_first_name_email"
    end

    it "should return shortened index name by shortening table and column names" do
      @conn.index_name("employees", :column => ["first_name", "last_name"]).should == "i_emp_fir_nam_las_nam"
    end

    it "should raise error if too large index name cannot be shortened" do
      lambda do
        @conn.index_name("test_employees", :column => ["first_name", "middle_name", "last_name"])
      end.should raise_error(ArgumentError)
    end

  end

  describe "ignore options for LOB columns" do
    after(:each) do
      schema_define do
        drop_table :test_posts
      end
    end

    it "should ignore :limit option for :text column" do
      lambda do
        schema_define do
          create_table :test_posts, :force => true do |t|
            t.text :body, :limit => 10000
          end
        end
      end.should_not raise_error
    end

    it "should ignore :limit option for :binary column" do
      lambda do
        schema_define do
          create_table :test_posts, :force => true do |t|
            t.binary :picture, :limit => 10000
          end
        end
      end.should_not raise_error
    end

  end

  describe "foreign key constraints" do
    before(:each) do
      schema_define do
        create_table :test_posts, :force => true do |t|
          t.string :title
        end
        create_table :test_comments, :force => true do |t|
          t.string :body, :limit => 4000
          t.references :test_post
          t.integer :post_id
        end
      end
      class ::TestPost < ActiveRecord::Base
        has_many :test_comments
      end
      class ::TestComment < ActiveRecord::Base
        belongs_to :test_post
      end
    end
    
    after(:each) do
      Object.send(:remove_const, "TestPost")
      Object.send(:remove_const, "TestComment")
      schema_define do
        drop_table :test_comments rescue nil
        drop_table :test_posts rescue nil
      end
    end

    it "should add foreign key" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291.*\.TEST_COMMENTS_TEST_POST_ID_FK/}
    end

    it "should add foreign key with name" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :name => "comments_posts_fk"
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291.*\.COMMENTS_POSTS_FK/}
    end

    it "should add foreign key with long name which is shortened" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :name => "test_comments_test_post_id_foreign_key"
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291.*\.TES_COM_TES_POS_ID_FOR_KEY/}
    end

    it "should add foreign key with very long name which is shortened" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :name => "long_prefix_test_comments_test_post_id_foreign_key"
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~
        /ORA-02291.*\.C#{Digest::SHA1.hexdigest("long_prefix_test_comments_test_post_id_foreign_key")[0,29].upcase}/}
    end

    it "should add foreign key with column" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :column => "post_id"
      end
      lambda do
        TestComment.create(:body => "test", :post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291.*\.TEST_COMMENTS_POST_ID_FK/}
    end

    it "should add foreign key with delete dependency" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :dependent => :delete
      end
      p = TestPost.create(:title => "test")
      c = TestComment.create(:body => "test", :test_post => p)
      TestPost.delete(p.id)
      TestComment.find_by_id(c.id).should be_nil
    end

    it "should add foreign key with nullify dependency" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :dependent => :nullify
      end
      p = TestPost.create(:title => "test")
      c = TestComment.create(:body => "test", :test_post => p)
      TestPost.delete(p.id)
      TestComment.find_by_id(c.id).test_post_id.should be_nil
    end

    it "should remove foreign key by table name" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
        remove_foreign_key :test_comments, :test_posts
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should_not raise_error
    end

    it "should remove foreign key by constraint name" do
      schema_define do
        add_foreign_key :test_comments, :test_posts, :name => "comments_posts_fk"
        remove_foreign_key :test_comments, :name => "comments_posts_fk"
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should_not raise_error
    end

    it "should remove foreign key by column name" do
      schema_define do
        add_foreign_key :test_comments, :test_posts
        remove_foreign_key :test_comments, :column => "test_post_id"
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should_not raise_error
    end

  end

  describe "foreign key in table definition" do
    before(:each) do
      schema_define do
        create_table :test_posts, :force => true do |t|
          t.string :title
        end
      end
      class ::TestPost < ActiveRecord::Base
        has_many :test_comments
      end
      class ::TestComment < ActiveRecord::Base
        belongs_to :test_post
      end
    end
    
    after(:each) do
      Object.send(:remove_const, "TestPost")
      Object.send(:remove_const, "TestComment")
      schema_define do
        drop_table :test_comments rescue nil
        drop_table :test_posts rescue nil
      end
    end

    it "should add foreign key in create_table" do
      schema_define do
        create_table :test_comments, :force => true do |t|
          t.string :body, :limit => 4000
          t.references :test_post
          t.foreign_key :test_posts
        end
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291/}
    end

    it "should add foreign key in create_table references" do
      schema_define do
        create_table :test_comments, :force => true do |t|
          t.string :body, :limit => 4000
          t.references :test_post, :foreign_key => true
        end
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291/}
    end

    it "should add foreign key in change_table" do
      schema_define do
        create_table :test_comments, :force => true do |t|
          t.string :body, :limit => 4000
          t.references :test_post
        end
        change_table :test_comments do |t|
          t.foreign_key :test_posts
        end
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291/}
    end

    it "should add foreign key in change_table references" do
      schema_define do
        create_table :test_comments, :force => true do |t|
          t.string :body, :limit => 4000
        end
        change_table :test_comments do |t|
          t.references :test_post, :foreign_key => true
        end
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should raise_error() {|e| e.message.should =~ /ORA-02291/}
    end

    it "should remove foreign key by table name" do
      schema_define do
        create_table :test_comments, :force => true do |t|
          t.string :body, :limit => 4000
          t.references :test_post
        end
        change_table :test_comments do |t|
          t.foreign_key :test_posts
        end
        change_table :test_comments do |t|
          t.remove_foreign_key :test_posts
        end
      end
      lambda do
        TestComment.create(:body => "test", :test_post_id => 1)
      end.should_not raise_error
    end

  end

end