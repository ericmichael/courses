require File.dirname(__FILE__) + '/../spec_helper'

describe UsersController do

  fixtures :accounts, :users


  before(:each) do
    controller.stubs(:current_account).returns(@account = accounts(:localhost))
    @admin = @account.users.where(:admin => true).first
    @user = @account.users.where(:admin => false).first
  end

  it "should prevent listing users if not logged in" do
    get :index
    response.should redirect_to(new_user_session_url)
  end

  describe "with normal users" do
    before(:each) do
      sign_in @user
    end

    it "should allow viewing the index" do
      get :index
      response.should render_template('index')
      assigns(:users).size.should == @account.users.size
    end

    it "should prevent adding new users" do
      get :new
      response.should redirect_to(new_user_session_url)
    end

    it "should prevent creating users" do
      post :create, :user => { :name => 'bob' }
      response.should redirect_to(new_user_session_url)
    end

    it "should prevent editing users" do
      get :edit, :id => @user.id
      response.should redirect_to(new_user_session_url)
    end

    it "should prevent updating users" do
      put :update, :id => @user.id, :user => { :name => 'bob' }
      response.should redirect_to(new_user_session_url)
    end
  end

  describe "as admin user" do
    before(:each) do
      sign_in @admin
      @account.stubs(:reached_user_limit?).returns(false)
    end

    it "should allow viewing the index" do
      get :index
      response.should render_template('index')
      assigns(:users).size.should == @account.users.size
    end

    it "should allow adding users" do
      get :new
      assigns(:user).account_id.should == @account.id
      response.should render_template('new')
    end

    it "should allow creating users" do
      lambda { post :create, :user => FactoryGirl.attributes_for(:user) }.should change(User, :count).by(1)
      response.should redirect_to(users_url)
    end

    it "should allow editing users" do
      get :edit, :id => @user.id
      response.should render_template('edit')
    end

    it "should allow updating users" do
      user = FactoryGirl.attributes_for(:user)
      lambda { put :update, :id => @user.id, :user => user }.should change { @user.reload.name }.to(user[:name])
      response.should redirect_to(users_url)
    end

    it "should prevent creating users when the user limit has been reached" do
      @account.expects(:reached_user_limit?).returns(true)
      lambda { post :create, :user => FactoryGirl.attributes_for(:user) }.should_not change(User, :count)
      response.should redirect_to(new_user_url)
    end
  end
end
