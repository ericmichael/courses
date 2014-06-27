require File.dirname(__FILE__) + '/../../spec_helper'

describe "/users/new.html.erb" do

  fixtures :users, :accounts, :subscriptions

  before(:each) do
    assign(:user, User.new)
    view.stubs(:current_account).returns(@account = accounts(:localhost))
  end
  
  describe "when the user limit has been reached" do
    before(:each) do
      @account.subscription.update_attribute(:user_limit, @account.users.count)
      render
    end
    
    it "should show text explaining the limit" do
      rendered.should =~ /You have reached the maximum number of users you can have with your account level./
    end

    it "should not show the form" do
      rendered.should_not have_selector('form')
    end
  end
  
  describe "when the limit has not been reached" do
    before(:each) do
      render
    end
    
    it "should show the form" do
      rendered.should have_selector('form', :action => users_path)
    end
  
    it "should not show the text explaining the limit" do
      rendered.should_not =~ /You have reached the maximum number of open users you can have with your account level./
    end
  end
end
