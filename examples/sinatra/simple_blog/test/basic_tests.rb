require 'rubygems'
require 'minitest/spec'

MiniTest::Unit.autorun

Exception.install_debug_block do |e|
  puts "====== #{e.class}:  #{e}"
  nil.pause if ArgumentError === e
end
describe Post do
  it "Adds newly created posts to the persistent root" do
    p0 = Post.new(:title => "The Title", :text => "Some text")
    p1 = Post.get(p0.__id__)
    p1.must_equal p0
  end

  it "Returns the newly created posts" do
    posts = Post.all
    titles = posts.map{ |p| p.title }
    titles.must_include(["The Title"])
  end
end

describe Tag do
  it "Adds newly created tags to the persistent root" do
    t0 = Tag.new("magleviathon")
    t1 = Tag.get(t0.__id__)
    t1.must_equal t0
  end
end