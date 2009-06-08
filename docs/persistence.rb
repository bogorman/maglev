#--
##############################################################################
#
#   P E R S I S T E N C E  A P I
#
##############################################################################

# A quick guide to the Transient / Persistent semantics:
#
#  |-------------+----------------------------+----------------------------|
#  |             | Maglev.persistent          | Maglev.transient           |
#  |-------------+----------------------------+----------------------------|
#  | Persistent  | * Constant -> both         | * Constant -> transient    |
#  | receiver    | * method -> both           | * method -> session        |
#  |-------------+----------------------------+----------------------------|
#  | Transient   | * Constant -> transient    | * Constant -> transient    |
#  | receiver    | * method -> session        | * method -> session        |
#  |-------------+----------------------------+----------------------------|
#  | New Class   | * Class marked persistent  | * Class marked transient   |
#  |             | * Name: according to rules | * Name: according to rules |
#  |             | of parent namespace        | of parent namespace        |
#  |-------------+----------------------------+----------------------------|
#
#++

# The Maglev module contains MagLev specific APIs.  Most MagLev specific
# features are rooted under this module, but a few features are placed
# elsewhere (e.g., in +Module+).
#
# Note that eigenclasses (singleton classes) are always marked persistable
# and are always marked to allow instances to be persisted.  Eigenclasses
# are persisted when their corresponding Ruby object is persisted (by
# reachability).
module Maglev
  # The root for all Maglev exceptions
  class MaglevException < StandardError;  end

  # Raised for operations that require a persistable receiver
  class NotPersistableException < MaglevException;  end

  # A Hash that is the root for persistent objects.  In a fresh repository,
  # this is initialized with an empty Ruby Hash.  After the first commit,
  # the contents of this Hash will be refreshed from the repository at each
  # <tt>Maglev.abort_transaction</tt>, <tt>Maglev.commit_transaction</tt>
  # and at VM startup.
  PERSISTENT_ROOT = Hash.new

  # Maglev.transient(&block)
  #
  # Executes the block with the VM in transient mode, which affects the
  # following operations:
  #
  # 1. All newly defined modules and classes will be marked as transient,
  #    and their names will be registered under the transient slot of the
  #    appropriate namespace (i.e., the constants that refer to the new
  #    classes will not be written to the repository during a
  #    <tt>Maglev.commit_transaction</tt>).
  #
  # 2. All assignments to constants will happen in the transient namespace,
  #    even for persistent modules and classes.
  #
  # 3. All method definitions in re-opened classes and modules will be
  #    placed into the transient dictionaries and not be available for
  #    persistence (but see <tt>Module#maglev_persist=</tt>).
  #
  # 4. All methods defined via <tt>Object#extend</tt> or
  #    <tt>Module#include</tt> will be done transiently, even if the target
  #    class or module is marked persistable.
  #
  # If the VM is already in transient mode, the block is executed and the
  # VM remains in transient mode (i.e., a no-op).
  #
  # == Example
  #
  # Suppose we have a running VM, and there already exist a persistent
  # module named +Persistent+, and a transient module named +Transient+.
  # We then run the following code:
  #
  #   Maglev.transient do
  #
  #     module Persistent   # a previously defined, persistent module
  #       class C           # A brand new class
  #         A_CONST = 42
  #         def foo
  #         end
  #       end
  #     end
  #
  #     Maglev::PERSISTENT_ROOT['foo'] = Persistent::C
  #
  #     Persistent::X = 42
  #     Transient::X  = 42
  #
  #   end
  #
  #   Maglev.commit_transaction
  #
  # After the code runs, the following statements hold:
  #
  # 1. Module +Persistent+ is still persisted in the repository, and module
  #    +Transient+ is still local to this VM.
  #
  # 2. <tt>Persistent::C</tt> is a constant in <tt>Persistent</tt>'s transient
  #    namespace, so will not have been written to the repository.  The
  #    current VM will still see <tt>Persistent::C</tt>.
  #
  # 3. <tt>Persistent::C</tt> is a class that is itself not persistable,
  #    nor are its instances persistable.
  #
  # 4. All methods and constants in <tt>Persistent::C</tt>,
  #    (<tt>Persistent::C::A_CONST</tt> and <tt>Persistent::C#foo</tt> will
  #    be lost (as will +C+) when the VM shuts down.
  #
  # 5. <tt>Maglev::PERSISTENT_ROOT['foo'] = Persistent::C</tt> will raise an
  #    exception at commit time (since +C+ is not persistable).
  #
  # 6. For <tt>Transient::X = 42</tt>, both the constant and its value are
  #    visible to the current VM, but not saved in the repository.
  #
  # 7. For <tt>Persistent::X = 42</tt>, both the constant +X+ and its
  #    current value (42) are visible to the current VM.  The repository
  #    will see the constant <tt>Persistent::X</tt> only if it was in the
  #    repository prior to the commit, and if it was, the repository will
  #    see the previous value.
  #
  # Calls to +transient+ may be nested inside other calls to +transient+
  # and calls to +persistent+.
  #
  def transient(&block)
    # ...
  end

  # Maglev.persistent(persistable_instances=true, &block)
  #
  # Executes the block with the VM in persistent mode, which affects the
  # following operations:
  #
  # 1. All newly defined modules and classes will be marked as persistable,
  #    and their names will be registered under the rules for the
  #    appropriate namespace (i.e., if the parent namespace is persistent,
  #    then the constant will be staged for persistence; if the parent
  #    namespace is transient, the constant reference will not be visible
  #    to the persistent store).
  #
  # 2. For new class definitions, if the <tt>persistable_instances</tt>
  #    flag is set to +true+, then the VM will also mark the class so that
  #    instances of that class may also be persisted.  If the flag is
  #    +false+, then the class, but not its instances, will be persistable
  #    (this allows you to load and commit library code for performance).
  #
  # 3. All assignments to constants in persistent classes and modules will
  #    be seen by the repository at the next
  #    <tt>Maglev.commit_transaction</tt>.  Any assignment to constants in
  #    transient classes and modules will be visible in the current VM, but
  #    will not be saved to the repository.
  #
  # 4. All method definitions in re-opened persistent classes and modules
  #    will be placed into both the transient and persistent method
  #    dictionaries and will be available for persistence.  It does not
  #    matter how the method is defined (e.g., <tt>define_method</tt>,
  #    <tt>module_eval</tt>, etc.).
  #
  #    All method definitions in re-opened transient classes and modules
  #    will be available only to the current VM and will not be persisted
  #    (i.e., defining a method on a transient class during persistent mode
  #    does not change the class to be persistent).
  #
  # 5. All methods defined via <tt>Object#extend</tt> or
  #    <tt>Module#include</tt> will be done persistently.
  #
  # If the VM is already in persistent mode, the block is executed and the
  # VM remains in persistent mode (i.e., a no-op).
  #
  # == Example
  #
  # Suppose we have a running VM, and there already exist a persistent
  # module named +Persistent+, and a transient module named +Transient+.
  # We then run the following code:
  #
  #   Maglev.persistent do
  #
  #     module Persistent   # a previously defined, persistent module
  #       class C           # A brand new class
  #         A_CONST = 42
  #         def foo
  #         end
  #       end
  #     end
  #
  #     Maglev::PERSISTENT_ROOT['foo'] = Persistent::C
  #
  #     Persistent::X = 42
  #     Transient::X  = 42
  #
  #   end
  #
  #   Maglev.commit_transaction
  #
  # After the code runs, the following statements hold:
  #
  # 1. Module +Persistent+ is still persisted in the repository, and module
  #    +Transient+ is still local to this VM.
  #
  # 2. <tt>Persistent::C</tt> is a constant in <tt>Persistent</tt>'s persistent
  #    namespace, so will have been written to the repository.
  #
  # 3. <tt>Persistent::C</tt> is a class that is itself persistable, and
  #    its instances are also persistable.
  #
  # 4. All methods and constants in <tt>Persistent::C</tt>,
  #    (<tt>Persistent::C::A_CONST</tt> and <tt>Persistent::C#foo</tt> will
  #    be saved to the repository.
  #
  # 5. <tt>Maglev::PERSISTENT_ROOT['foo'] = Persistent::C</tt> will be
  #    committed to the repository and be available to all VMs.
  #
  # 6. For <tt>Transient::X = 42</tt>, both the constant and its value are
  #    visible to the current VM, but not saved in the repository.
  #
  # 7. For <tt>Persistent::X = 42</tt>, both the constant +X+ and its
  #    current value (42) are visible to the current VM and saved in the
  #    repository.
  #
  # Calls to +persistent+ may be nested inside calls to +transient+ and
  # other calls to +persistent+.
  #
  def persistent(persistable_instances=true, &block)
    # ...
  end

  module_function :transient, :persistent
end

class Module
  # Controls whether receiver is persistable.
  #
  # If the +flag+ is true, then receiver is marked to allow itself to be
  # persisted.  Since Modules and Classes are namespaces, all of receivers
  # constants should hold persistable values or an exception will be raised
  # at commit time.
  #
  # If the +flag+ is false, then receiver is marked to disallow itself to
  # be persisted.  Receiver and its instances should be removed from
  # persistent roots before the next <tt>Maglev.commit_transaction</tt>.
  #
  # If receiver is a class, this method does not affect the persistable
  # instances flag (which is set to true by default). See
  # <tt>Class#maglev_persistable_instances</tt> for controlling whether
  # instances of the class are persistable.
  #
  # TODO: Should we add an instances_persistable=true flag?
  def maglev_persistable=(flag=true)
    # ...
  end

  # Returns the persistable flag of receiver
  def maglev_persistable?
    # ...
  end
end

class Class
  # Controls whether instances of receiver are persistable.  If the flag is
  # +true+, then receiver is marked to allow instances to be persisted.
  #
  # If the flag is +false+, then receiver is marked to disallow instances
  # to be persisted.  If reciever was previously marked to allow
  # persistable instances, and instances have been committed to the
  # repository, the call will succeed, and all further instances will not
  # be committable.  The previously persisted instances remain in the
  # repository (and will hold a reference to receiver) until they are
  # cleared by the program.
  #
  # Raises +NotPersistableException+ if reciever is not persistable.
  #
  def maglev_instances_persistable=(flag=true)
    raise NotPersistableException unless self.maglev_persistable?
    # ...
  end

  # Returns +true+ if instances of receiver are allowed to be
  # persisted. Returns +false+ otherwise.
  def maglev_instances_persistable?
    # ...
  end
end


#--
##############################################################################
#
#   T R A N S A C T I O N   A P I
#
##############################################################################
#++

module Maglev
  class OutsideOfTransactionException < Maglev::MaglevException; end

  # This exception is raised if MagLev is unable to commit the state of the
  # repository.  The details of why the commit failed are contained in the
  # exception.
  class CommitFailedException < MagLev::MaglevException
    # TODO: De-smalltalk-ify description and API
    #
    # Returns a SymbolDictionary that contains an Association whose key is
    # #commitResult and whose value is one of the following Symbols:
    # #success, #failure, #retryFailure, #commitDisallowed, or #rcFailure .
    #
    # The remaining Associations in the dictionary are used to report the
    # conflicts found.  Each Association's key indicates the kind of
    # conflict detected; its associated value is an Array of OOPs for the
    # objects that are conflicting.  If there are no conflicts for the
    # transaction, the returned SymbolDictionary has no additional
    # Associations.
    #
    # The conflict sets are cleared at the beginning of a commit or abort
    # and therefore may be examined until the next commit, continue or
    # abort.
    #
    # The keys for the conflicts are as follows:
    #
    #     Key                Conflicts
    # Read-Write          StrongReadSet and WriteSetUnion conflicts.
    # Write-Write         WriteSet and WriteSetUnion conflicts.
    # Write-Dependency    WriteSet and DependencyChangeSetUnion conflicts.
    # Write-WriteLock     WriteSet and WriteLockSet conflicts.
    # Write-ReadLock      WriteSet and ReadLockSet conflicts.
    # Rc-Write-Write      Logical write-write conflict on reduced conflict object.
    # WriteWrite_minusRcReadSet  (WriteSet and WriteSetUnion conflicts) - RcReadSet)
    #
    # The Read-Write conflict set has already had RcReadSet subtracted from
    # it.  The Write-Write conflict set does not have RcReadSet subtracted.
    #
    # Beginning with Gemstone64 v1.1 , the WriteSet no longer includes
    # objects newly committed by this transaction.  Thus a conflict between
    # a lock and a newly committed object in prior releases will no longer
    # show up as a conflict.
    #
    # The Write-Dependency conflict set contains objects modified
    # (including DependencyMap operations) in the current transaction that
    # were either added to, removed from, or changed in the DependencyMap
    # by another transaction. Objects in the Write-Dependency conflict set
    # may be in the Write-Write conflict set.
    #
    # Note: You should be sure to disconnect conflict sets before
    # committing to avoid making them persistent.
    def transaction_conflicts
      raise NotImplementedError
    end

    # TODO: Should we have something simple like this to handle the "Note"
    # at the end of the description for transaction_conflicts?
    #
    # Disconnect (ignore) all conflicts
    def disconnect_conflicts
    end
  end

  # Attempts to update the persistent state of the Repository to include
  # changes made by this transaction.
  #
  # If the commit operation succeeds, then this method returns true, and
  # the current transaction's changes, if any, become a part of the
  # persistent Repository.  After the repository update, the session exits
  # the current transaction.  If the transaction mode is :auto_begin (the
  # MagLev default), then the session enters a new transaction.  If the
  # transaction mode is :manual_begin, then the session remains outside of
  # a transaction.
  #
  # If conflicts prevent the repository update, then this method raises a
  # CommitFailedException which contains details of why the commit failed.
  # Call the transaction_conflicts method to determine the nature of the
  # conflicts.  If the session is outside of a transaction, then this
  # method raises the error OutsideOfTransactionException
  #
  # This method also updates the session's view of GemStone.  If the commit
  # operation succeeds, then all objects in the session's view are
  # consistent with the current state of GemStone.  If the commit fails,
  # then this method retains all the changes that were made to objects
  # within the current transaction.  However, commits made by other
  # sessions are visible to the extent that changes in this transaction do
  # not conflict with them.
  #
  # Returns true if commit was read-only or succeeded.  Raises
  # OutsideOfTransactionException if there was a failure.
  def commit_transaction
    # TODO: wrap #rtErrPrimOutsideTrans in OutsideOfTransactionException
    unless Gemstone.commitTransaction
      raise CommitFailedException
    end
    return true
  end

  # Rolls back all modifications made to committed GemStone objects and
  # provides the session with a new view of the most recently committed
  # GemStone state.
  #
  # These operations are performed whether or not the session was
  # previously in a transaction.  If the transaction mode is set to
  # :auto_begin, then a new transaction is started.  If the transaction
  # mode is set to :manual_begin, then a new transaction is not started.
  def abort_transaction
    return Gemstone.abort_transaction
  end

  module_function :commit_transaction, :abort_transaction
end