defmodule Sahla.Accounts.PolicyTest do
  use ExUnit.Case, async: true

  alias Sahla.Accounts.Policy

  test "superadmin holds every capability" do
    for capability <- Policy.all_capabilities() do
      assert Policy.can?(:superadmin, capability)
    end
  end

  test "each role holds exactly its mapped capabilities" do
    assert Policy.can?(:ops, :leads)
    assert Policy.can?(:ops, :simulator)
    refute Policy.can?(:ops, :cms)

    assert Policy.can?(:agent, :leads_assigned)
    refute Policy.can?(:agent, :leads)

    assert Policy.can?(:editor, :cms)
    refute Policy.can?(:editor, :leads)

    assert Policy.can?(:finance, :finance_exports)
    refute Policy.can?(:finance, :cms)
  end

  test "manage_admins and publish_rate_tables are superadmin-only" do
    for role <- [:ops, :agent, :editor, :finance] do
      refute Policy.can?(role, :manage_admins)
      refute Policy.can?(role, :publish_rate_tables)
    end

    assert Policy.can?(:superadmin, :manage_admins)
    assert Policy.can?(:superadmin, :publish_rate_tables)
  end

  test "an unknown role holds nothing" do
    refute Policy.can?(:ghost, :leads)
  end
end
