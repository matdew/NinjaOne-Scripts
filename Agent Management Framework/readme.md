## **Overview**

General approach is designed for consistent techniques, scripts, and monitors for managing MSP-sold agents, including (e.g. SentinelOne, DNSFilter, ArcticWolf, ConnectSecure, Huntress, etc...) This is not intended for client-specific applications.

Custom Fields to set desired behavior of the agent and input variable data required for agent installation, such as install tokens.

Policies are used to apply compound conditions that check the desired deployment behavior and initiate installation/uninstallation, as well as monitor agent service statuses.

A single Automation/Script is used to Install, Uninstall, Reinstall (when broken), and Uninstall and Prevent Reinstallation (set custom field override) - Script in this directory.

## **Critical Pieces**

## **Automation Library - Script**

- Create a new Script using the template in this directory.
- Name: \<App Name> Agent Management
- Provide a description and categories according to *\<your standards and guidelines>*
- Include the Software category at a minimum.
- Add a Script Variable
    - Type: Dropdown
    - Name: Manual Override
    - Option Values:
        - Install
        - Reinstall
        - Uninstall
        - Uninstall and Prevent Reinstallation
    - DO NOT MAKE MANDATORY - running without being set will automatically align with detected Deployment Behavior.
- Adjust the $env:agentDisplayName and $env:agentServiceName values to reflect the app
    - Display Name is purely for logging purposes
    - Service Name is the Windows Service _Name_, not Display Name.
        
- Adjust the $env:deploymentBehaviorCustomFieldName value to reflect the correct field.
- Retrieve any other required fields, such as installation tokens and variables at the top of the script using Get-NinjaProperty calls.
- Add the agent installation and uninstallation script logic within their respective functions.

## **Automation Library - Toolkit Script (optional)**

Separate from the lifecycle (install/uninstall/reinstall) management script, a *toolkit* script is useful for the ancillary actions you run against an agent that is **already installed** - restarting the service, tweaking a setting, gathering diagnostic logs, etc. Keeping these out of the management script avoids cluttering the lifecycle logic and keeps each concern separate. Use the toolkit template in this directory as a starting point.

- Create a new Script using the toolkit template in this directory.
- Name: \<App Name> Toolkit
- Provide a description and categories according to *\<your standards and guidelines>*
- Include the Software category at a minimum.
- Add a Script Variable
    - Type: Dropdown
    - Name: Action
    - Option Values: one per action the toolkit supports (e.g. Restart Service, Apply Configuration, Gather Diagnostics)
    - Consider making this Mandatory, since - unlike the management script - there is no "detected behavior" fallback; an unset action just errors out.
- Adjust the $env:agentDisplayName, $env:agentServiceName, and $env:logDirectory values to reflect the app and your standards.
- Add one function per action, then wire each into the switch statement at the bottom. The switch labels must EXACTLY match the Dropdown option values.
- Remove any example actions you don't need, and add your own (registry/config tweaks, cache clears, re-registration, targeted service control, etc.).
- Retrieve any required fields (tokens, IDs, region, etc.) at the top of the script using Get-NinjaProperty calls, just as with the management script.

## **Custom Fields**

- Deployment Behavior
    - Field Name/Label: App-Name Deployment Behavior
    - Type: Dropdown
    - NOT REQUIRED - allow to not be set
    - Inheritance: Org, Location, and Device in most cases.
    - Permissions:
        - Automations: READ/WRITE (Automations must be able to read this value to confirm what's set, must Write to self-exclude when manual run includes exclusion [explained further in script section])
        - API: READ (READ/WRITE in some cases)
        - Technician access: EDITABLE
    - Details: Please include any scripts/APIs that refer to this field (see *your standards and guidelines>*) in the Description. Tooltip should explain that this field changes application deployment behavior.
    - Advanced settings: Create 3 options, "Install", "No Action" (Mark as Default), "Uninstall"
- Installation Tokens/Keys
    - For sensitive/privileged tokens or extremely long ones, use a Secure field. Secure fields not only mask the data and log access, but the masking reduces visual clutter on Custom Field screens. If the string is simple and not sensitive, use the Text field type.
    - Ensure they use a similar naming convention (e.g. \<AppName> Token, \<AppName> Key)
    - Scope them appropriately on the Inheritance screen, it is unlikely a company-wide install key will need to be overridden at the location or device level.
    - For truly global values that apply to every org - such as a single deployment token or account ID shared across all clients - use a **System** level field. System is an inheritance level above Org, so the value is set once and applies everywhere without needing per-org overrides. Only enable lower inheritance levels (Org, Location, Device) if you actually expect to override the value somewhere; otherwise leave it at System to reduce clutter and prevent accidental per-org changes.
    - Set permissions appropriately for these global fields. Because a System-level token or account ID is shared across all clients, restrict Technician access so co-managed client roles and Tier 1 helpdesk get **Read** or **No Access** (never Editable). This prevents a client-facing or lower-tier technician from viewing/changing a value that affects your entire fleet. Reserve Edit access for the roles that manage the framework itself.
- Other Fields as Needed
    - Use a similar naming convention (e.g. \<AppName> Install Type, \<AppName> Org ID, \<Appname> Region)
    - Scope them appropriately on the inheritance screen. As with tokens, prefer a **System** level field for any value that is truly global across all orgs, and only add Org/Location/Device inheritance when per-org overrides are actually needed.
    - Note: the Deployment Behavior field is an exception - it is intended to be overridden per Org/Location/Device, so it should not be scoped to System only.

## **Policies**

- Edit the  Policies for each device Type (Windows Server, Windows Workstation, Mac Workstation, etc...)
    
    Base
    
    - Client policies inherit from these base policies. ***\<this may not be true in your enviroment, adjust as needed>***
- Create a Compound Condition for Installation.
    - Trigger when all conditions are met.
        - Custom Field: \<App> Deployment Behavior - Equals - Install
        - Windows Service: \<App service> - Any - Doesn't exist
            - Adjust as needed based on the agent, could also be Software Doesn't exist.
    - Automations: Select the agent management Script with no parameters/variables set.
    - Settings:
        - Naming convention: Agent Deployment: \<App/Agent name>
        - Auto Reset when no longer met - Always Checked
        - Auto Reset After X hours - Completely clears the condition - use to automatically retry for installation failures.
        - Run every X hours - how often to re-evaluate the trigger conditions (if condition is still triggered, this will not rerun automations until cleared/reset)
        - Minimum uptime - 10 minutes or so.
    - Notifications - usually left unconfigured.
- Create a Compound Condition for Removal
    - Repeat same settings as Installation with the following adjustments
    - Name should be Agent Removal: \<App/Agent Name>
    - Condition checks will be inverted (Deployment Behavior is Uninstall and Service/Software Does Exist)
- Agent monitoring Compound Conditions
    - Create additional compound conditions and automations as needed.
        - i.e. Deployment Behavior is set to Install and Service Exists but is Stopped > Run Automation "Start or Stop - Windows Service"

## **Groups (optional)**

- Create Device Groups for "Agent: Should be Installed" and "Agent Should be Removed"
- Base these on the custom field values.
- These are for automations/APIs/reporting.
