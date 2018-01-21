<#
Enumerate all events in the manifest and create a hash table of event id to message id.
>  $manifest.assembly.instrumentation.events.provider.events.event

Enumerate all messages in the manifest and create a hash table of message id to message data.
> $manifest.assembly.localization.resources.stringTable.string
> Message data will be the message text and the number of replaceable parameters in the message.
> Only messages referenced by event ids will be in the table.

Generate a resx file containing the messages.
Generate a static C# class containing
> A hash table mapping event id to message data (resource path, resource id, and the number of replaceable parameters)
> A static method for formatting the message to log and calling the native SysLog.

NOTE: A native binary will also need to be generated that wraps the call to syslog and exports a function to call from
managed code.  The static method mentioned above will call this export through PInvoke.
#>

using namespace System.Collections.Generic
using namespace System.Globalization
using namespace System.Xml

#region resx string templates

# Defines the start of the resx file.
# String.Format arguments
# {0} The name of the manifest file used to produce the resx
[string] $resxPrologue = @"
<?xml version="1.0" encoding="utf-8"?>
<root>
<!--
    This code was generated by the tools\ResxGen\ResxGen.ps1 run against {0}.
    To add or change logged events and the associated resources, edit {0}
    then rerun ResxGen.ps1 to produce an updated CS and Resx file.
-->
<xsd:schema id="root" xmlns="" xmlns:xsd="https://www.w3.org/2001/XMLSchema" xmlns:msdata="urn:schemas-microsoft-com:xml-msdata">
<xsd:import namespace="https://www.w3.org/XML/1998/namespace" />
<xsd:element name="root" msdata:IsDataSet="true">
  <xsd:complexType>
    <xsd:choice maxOccurs="unbounded">
      <xsd:element name="metadata">
        <xsd:complexType>
          <xsd:sequence>
            <xsd:element name="value" type="xsd:string" minOccurs="0" />
          </xsd:sequence>
          <xsd:attribute name="name" use="required" type="xsd:string" />
          <xsd:attribute name="type" type="xsd:string" />
          <xsd:attribute name="mimetype" type="xsd:string" />
          <xsd:attribute ref="xml:space" />
        </xsd:complexType>
      </xsd:element>
      <xsd:element name="assembly">
        <xsd:complexType>
          <xsd:attribute name="alias" type="xsd:string" />
          <xsd:attribute name="name" type="xsd:string" />
        </xsd:complexType>
      </xsd:element>
      <xsd:element name="data">
        <xsd:complexType>
          <xsd:sequence>
            <xsd:element name="value" type="xsd:string" minOccurs="0" msdata:Ordinal="1" />
            <xsd:element name="comment" type="xsd:string" minOccurs="0" msdata:Ordinal="2" />
          </xsd:sequence>
          <xsd:attribute name="name" type="xsd:string" use="required" msdata:Ordinal="1" />
          <xsd:attribute name="type" type="xsd:string" msdata:Ordinal="3" />
          <xsd:attribute name="mimetype" type="xsd:string" msdata:Ordinal="4" />
          <xsd:attribute ref="xml:space" />
        </xsd:complexType>
      </xsd:element>
      <xsd:element name="resheader">
        <xsd:complexType>
          <xsd:sequence>
            <xsd:element name="value" type="xsd:string" minOccurs="0" msdata:Ordinal="1" />
          </xsd:sequence>
          <xsd:attribute name="name" type="xsd:string" use="required" />
        </xsd:complexType>
      </xsd:element>
    </xsd:choice>
  </xsd:complexType>
</xsd:element>
</xsd:schema>
<resheader name="resmimetype">
    <value>text/microsoft-resx</value>
</resheader>
<resheader name="version">
    <value>2.0</value>
</resheader>
<resheader name="reader">
    <value>System.Resources.ResXResourceReader, System.Windows.Forms, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
</resheader>
<resheader name="writer">
    <value>System.Resources.ResXResourceWriter, System.Windows.Forms, Version=2.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089</value>
</resheader>
<data name="MissingEventIdMessage" xml:space="preserve">
    <value>A message was not found for event id {0}.</value>
</data>
"@

# Defines a template for each named string resource in the resx file.
# String.Format arguments
# {0} The name of the  resource
# {1} The value of the resource
[string] $resxEntryTemplate = @"

<data name="{0}" xml:space="preserve">
    <value>{1}</value>
</data>
"@

# Defines the end of the resx file.
# This should be appended after adding each named resource.
# String.Format arguments: None
[string] $resxEpilogue = @"

</root>
"@

#endregion resx string templates

#region C# code template strings

# Defines the start of the generated code.
# String.Format arguments
# {0} The namespace for the class
# {1} The class name
# {2} The name of the manifest file used to produce the code.
[string] $codePrologue = @'
#if UNIX
/*
    This code was generated by the tools\ResxGen\ResxGen.ps1 run against {2}.
    To add or change logged events and the associated resources, edit {2}
    then rerun ResxGen.ps1 to produce an updated CS and Resx file.
*/
using System.Collections.Generic;
using System.Management.Automation.Internal;
using System.Runtime.InteropServices;

namespace {0}
{{
    /// <summary>
    /// Provides a class for describing a message resource for an ETW event.
    /// </summary>
    internal static class {1}
    {{
        // Defines the resource id of the message to use when an event id is not valid.
        private const string MissingEventIdResourceName = "MissingEventIdMessage";

        /// <summary>
        /// Gets the name of the message resource to use for event ids that are not found.
        /// is not found.
        /// </summary>
        /// <remarks>
        /// This method is called when GetMessage returns a null value indicating the passed
        /// in event id was not found. The message should be used as the format string
        /// with the event id as the single variable argument.
        /// <remarks>
        public static string GetMissingEventMessage(out int parameterCount)
        {{
            parameterCount = 1;
            return MissingEventIdResourceName;
        }}

        /// <summary>
        /// Gets the message resource id for the specified event id
        /// </summary>
        /// <param name="eventId">The event id for the message resource to retrieve.</param>
        /// <param name="parameterCount">The number of parameters required by the message resource</param>
        /// <returns>The string resource id of the associated event message; otherwise, a null reference if the event id is not valid.</returns>
        public static string GetMessage(int eventId, out int parameterCount)
        {{
            switch (eventId)
            {{
'@

# Adds an entry to the eventid -> resource name dictionary
# String.Format arguments
# {0} - event id
# {1} - the resource id for the event message
# {2} - the number of parameters required to format the message. May be zero.
[string] $codeEventEntryTemplate = @"

                case {0}:
                    parameterCount = {2};
                    return "{1}";
"@

# defines the end of the generated C# code.
# String.Format arguments: None
[string] $codeEpilogue = @"

            }}
            parameterCount = 0;
            return null;
        }}
    }}
}}
#endif
"@

#endregion C# code template strings

<#
  Provides a class for encapsulating a resource string entry from an ETW manifest
#>
class EventMessage
{
    #region properties

    <#
      Gets the message id.
      This is used as a resource name.
    #>
    [string] $Id

    <#
      Gets the identifier used by an event to reference the message.
    #>
    [string] $EventReference

    <#
      The number of replaceable parameters in the message; from 0 through 99
      Used to determine if string.Format is needed.
    #>
    [int] $ParameterCount

    <#
      Gets the message text
    #>
    [string] $Value

    #endregion properties

    <#
    .SYNOPSIS
      replaces FormatMessage format specifiers with String.Format equivalent.

    .PARAMETER message
      The message string to update.

    .NOTES
      See https://msdn.microsoft.com/en-us/library/windows/desktop/ms679351(v=vs.85).aspx.
      Replaceable parameters are limited to %1 ... %99. Width and precision specifiers are
      not currently supported since the manifest does not use them at the time of this writing.
    #>
    hidden [void] SetMessage([string] $message)
    {
        foreach ($source in [EventMessage]::escapeStrings.Keys)
        {
            $dest = [EventMessage]::escapeStrings[$source]
            $message = $message.Replace($source, $dest)
        }

        [int] $paramCount = 0
        for ($index = 1; $index -le 99; $index++)
        {
            [string] $source = [string]::Format([CultureInfo]::InvariantCulture, '%{0}', $index)

            if ($message.Contains($source))
            {
                $paramCount = $index;
                # convert %1->%99 to {0}->{98}
                [string] $target = [string]::Format([CultureInfo]::InvariantCulture, '{0}{1}{2}', '{', $index - 1, '}')
                $message = $message.Replace($source, $target)
            }
        }
        $this.Value = $message
        $this.ParameterCount = $paramCount
    }

    EventMessage([XmlElement] $element)
    {
        $this.EventReference =[string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '$(string.{0})', $element.Id)
        [string] $messageId = $element.id
        if ($messageId.EndsWith('.message'))
        {
            $messageId = $messageId.Substring(0, $messageId.Length - '.message'.Length)
        }
        if ($messageId.Contains('.'))
        {
            $messageId = $messageId.Replace('.', '')
        }
        if ($messageId.Contains('-'))
        {
            $messageId = $messageId.Replace('-', '')
        }
        $this.Id = $messageId
        $this.SetMessage($element.value)
    }

    static hidden $escapeStrings =
    @{
        '%t' = "`t";
        '%n'="`n";
        '%r'="`r";
        '%%'='%';
        '%space'=' ';
        '%.'='.'
    }
}


enum LogLevel
{
    Always = 0
    Critical = 1
    Error = 2
    Warning = 3
    Information = 4
    Verbose = 5
}

class EventEntry
{
    [int] $EventId
    [string] $MessageReference
    [EventMessage] $EventMessage
    [string] $Channel
    [LogLevel] $Level
    [string]  $Task

    EventEntry ([XmlElement] $element)
    {
        $idValue = $element.value.Trim()
        if ($idValue.StartsWith('0x', [StringComparison]::OrdinalIgnoreCase))
        {
            $idValue = $idValue.SubString(2)
        }
        $this.EventId = [Int32]::Parse($idValue, [System.Globalization.NumberStyles]::HexNumber )
        $this.Channel = $element.channel
        $this.Level = [EventEntry]::levelNames[$element.level]
        $this.MessageReference = $element.message
        $this.Task = $element.Task
    }

    static hidden $levelNames =
    @{
        'win:Always' = [LogLevel]::Always;
        'win:Verbose' = [LogLevel]::Verbose;
        'win:Informational' = [LogLevel]::Information;
        'win:Warning' = [LogLevel]::Warning;
        'win:Error' = [LogLevel]::Error;
        'win:Critical' = [LogLevel]::Critical;
    }
}

class Manifest
{
    [string] $FileName
    [Dictionary[int, EventEntry]] $Events
    [Dictionary[string, EventMessage]] $Messages
    [Dictionary[string, string]] $Tasks
    [Dictionary[string, string]] $Opcodes
    [Dictionary[string, string]] $Channels

    Manifest([string] $Path)
    {
        if (-not (Test-Path -Path $Path))
        {
            throw "The manifest file was not found: $Path"
        }
        Write-Verbose -Message "Parsing $Path" -Verbose
        $this.FileName = Split-Path -Path $Path -Leaf -Resolve

        [xml] $man = Get-Content -Path $Path

        $messageTable = [Dictionary[string, EventMessage]]::new()
        foreach ($item in $man.assembly.localization.resources.stringTable.string)
        {
            $eventMessage = [EventMessage]::new($item)
            $messageTable.Add($eventMessage.EventReference, $eventMessage)
        }

        $this.Tasks =  [Dictionary[string, string]]::new()
        foreach ($item in $man.assembly.instrumentation.events.provider.tasks.task)
        {
            $this.Tasks.Add($item.Symbol, $item.Name)
        }

        $this.Opcodes = [Dictionary[string, string]]::new()
        foreach ($item in $man.assembly.instrumentation.events.provider.opcodes.opcode)
        {
            $this.Opcodes.Add($item.Symbol, $item.Name)
        }

        $this.Channels = [Dictionary[string, string]]::new()
        foreach ($item in $man.assembly.instrumentation.events.provider.channels.channel)
        {
            $this.Channels.Add($item.Symbol, $item.Type)
        }

        $this.Events = [Dictionary[int, EventMessage]]::new()
        foreach ($event in $man.assembly.instrumentation.events.provider.events.event)
        {
            [EventEntry] $eventEntry = [EventEntry]::new($event)
            $eventEntry.EventMessage = $messageTable[$eventEntry.MessageReference]
            $this.Events.Add($eventEntry.EventId, $eventEntry)
        }

        # NOTE: Build the final message dictionary.
        # $messageTable contains all strings defined in the manifest but not all are needed.
        # Some are for tasks, opcodes, channels, etc., and some events reference the same
        # message.
        $this.Messages = [Dictionary[int, EventMessage]]::new()
        foreach ($event in $this.Events.Values)
        {
            $eventMessage = $event.EventMessage
            if (!$this.Messages.ContainsKey($eventMessage.EventReference))
            {
                $this.Messages.Add($eventMessage.EventReference, $eventMessage)
            }
        }
    }
}

function New-ResourceCode
{
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [Manifest] $manifest,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $namespaceName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $className
    )
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendFormat($codePrologue, $namespaceName, $className, $manifest.FileName)
    # sort by event id for readability.
    $values = ($manifest.Events.Values | Sort-Object -Property 'EventId')
    foreach ($eventEntry in $values)
    {
        $null = $sb.AppendFormat($codeEventEntryTemplate, $eventEntry.EventId, $eventEntry.EventMessage.Id, $eventEntry.EventMessage.ParameterCount)
    }
    $null = $sb.Append($codeEpilogue)
    $code = $sb.ToString().Replace('}}', '}')
    return $code
}

<#
.SYNOPSIS
    Creates a resx file containing the messages from a manifest

.PARAMETER messages
    The EventMessage hash table containing the manifest messages
#>
function New-Resx
{
    param
    (
        [Manifest] $manifest
    )
    $messages = $manifest.Messages
    $sb = [System.Text.StringBuilder]::new()

    $null = $sb.AppendFormat($resxPrologue, $manifest.FileName)
    foreach ($message in $messages.Values)
    {
        $null = $sb.AppendFormat($resxEntryTemplate, $message.Id, $message.Value)
    }
    $null = $sb.Append($resxEpilogue)
    return $sb.ToString()
}

<#
.SYNOPSIS
    Generates a resx file and code file from an ETW manifest.

.PARAMETER Manifest
    The path to the ETW manifest file to read.

.PARAMETER Name
    The name to use for the C# class, the code file, and the resx file.
    The default value is EventResource.

.PARAMETER Namespace
    The namespace to place the C# class.
    The default is System.Management.Automation.Tracing.

.PARAMETER ResxPath
    The path to the directory to use to create the resx file.

.PARAMETER CodePath
    The path to the directory to use to create the C# code file.
#>
function ConvertTo-Resx
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Manifest,

        [string] $Name = 'EventResource',

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Namespace = 'System.Management.Automation.Tracing',

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ResxPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $CodePath
    )

    [Manifest] $etwmanifest = [Manifest]::new($Manifest)

    $resxFileName = Join-Path -Path $ResxPath -ChildPath "$($Name).resx"
    Write-Verbose -Message "Creating $resxFileName" -Verbose

    $resx = New-Resx -manifest $etwmanifest
    $resx | Set-Content -Path $resxFileName -Encoding 'ASCII'

    $codeFileName = Join-Path -Path $CodePath -ChildPath "$($Name).cs"
    Write-Verbose -Message "Creating $codeFileName" -Verbose

    $code = New-ResourceCode -manifest $etwmanifest -Namespace $Namespace -ClassName $Name
    $code | Set-Content -Path $codeFileName -Encoding 'ASCII'
}

Export-ModuleMember -Function ConvertTo-Resx
