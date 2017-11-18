#
#
# Copyright © 2017 Dell Inc. or its subsidiaries. All rights reserved.
# Dell, EMC, and other trademarks are trademarks of Dell Inc. or its
# subsidiaries. Other trademarks may be trademarks of their respective owners.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Authors: Vaideeswaran Ganesan
#

# Uncomment valid Attributes and place it inside the tree
#class T(ET.TreeBuilder):
#
#    def comment(self, data):
#        k = data.strip()
#        if re.match('<[^ >]+( [^>]+)*>[^<]*</[^>]+>', k):
#            t = ET.fromstring(k)
#            $this.start(t.tag, dict([(k, v) for (k,v) in t.items()]))
#            if not t.text: t.text = ""
#            $this.data(t.text)
#            $this.end(t.tag)




class SCPParser
{
    hidden $config_spec
    SCPParser($cspecfile)
    {
        $this.config_spec = {}
        if (($cspecfile -ne $null) -and (Test-Path $cspecfile))
        {
            $this.config_spec = (Get-content $cspecfile | ConvertFrom-Json)
        }
    }

    [object] _get_entry($comp_fqdd, $sysconfig)
    {
        write-host ">$comp_fqdd<"
        foreach ($i in (Get-Member -MemberType NoteProperty -InputObject $this.config_spec))
        {
            $entry = $this.config_spec.($i.Name)
            $pattern = Get-Member -InputObject $entry -Name 'pattern'
            if ($pattern -ne $null)
            {
                if ($entry.($pattern.Name) -match $comp_fqdd)
                {
                    if ($sysconfig.Properties() | where { $_.Name -eq $i.Name })
                    {
                        write-host ("=======Found Match {0} => {1}" -f $comp_fqdd, $i.Name)
                        return $sysconfig.($i.Name)
                    }
                }
            }
        }
        return $null
    }

    [void] _load_child($node, $entry)
    {
        foreach ($child in $node.ChildNodes)
        {
            if ($child.NodeType -eq 'Comment')
            {
                if ($child.InnerText -notmatch '<Attribute .*</Attribute>')
                {
                    continue
                }
                $child = [xml]($child.InnerText)
                if ($child.NodeType -eq 'Document')
                {
                    $child = $child.ChildNodes[0]
                }
            }
            if ($child.Name -eq 'Component')
            {
                $subnode = $this._get_entry($child.FQDD, $entry)
                write-host ($subnode)
                if ($subnode -eq $null)
                {
                    write-host('No component spec found for ' + $child.FQDD)
                    continue
                }
                $parent = $null
                $subentry = $subnode
                if ($subnode -is [ArrayType])
                {
                    $parent = $subnode
                    $subentry = $parent.find_or_create()
                }

                foreach ($attr in $child.attrib)
                {
                    $subentry.add_attribute($attr, $child.attrib[$attr])
                }
    
                $this._load_child($child, $subentry)
                continue
            }
    
            $attrname = $child.Name
            if ($attrname -eq $null)
            {
                write-host("ERROR: No attribute found!!")
                continue
            }
    
            if ($attrname.Contains('.') -eq $false)
            {
                # plain attribute
                if ( -not ($entry.Properties() | where { $_.Name -eq $attrname }) )
                {
                    write-host ("Not found: {0}" -f $attrname)
                    $entry.__setattr__($attrname, [StringField]::new($child.InnerText, @{Parent=$entry}))
                    write-host($attrname + ' not found in ' + $entry.GetType())
                    write-host("Ensure the attribute registry is updated.")
                    continue
                }
    
                if ($child.text -eq $null -or $child.text.strip() -eq '')
                {
                    # empty - what to do?
                    if ($entry.__dict__[$attrname]._type -eq [string])
                    {
                        $entry.__dict__[$attrname].Value = ""
                    }
                }
                else
                {
                    $entry.__dict__[$attrname].Value = $child.text.strip()
                }
                continue
            }
    
            $match = $attrname -split '(.*)\.([0-9]+)#(.*)'
            if ($match.Count -ne 5)
            {
                write-host($attrname + ' not good ')
                continue
            }
    
            $group = $match[1]
            $index = $match[2]
            $field = $match[3]
            if ($entry.Properties() | where { $_.Name -eq $group })
            {
                $grp = $entry.($group)
    
                $subentry = $grp
                if ($grp -is [ArrayType])
                {
                    $subentry = $grp.find_or_create([int]$index)
                }
    
                if (-not ($subentry.Properties() | where { $_.Name -eq $field }))
                {
                    $field = $field + '_' + $group
                }
                if (-not ($subentry.Properties() | where { $_.Name -eq $field }))
                {
                    $subentry.__setattr($field, [StringField]::new($child.InnerText, @{Parent=$subentry}))
                    write-host($field+' not found in '+ $subentry.getType())
                    write-host("Ensure the attribute registry is updated.")
                    continue
                }
                write-host($child.InnerText)
               
                if ($child.InnerText -eq $null -or $child.InnerText.Trim() -eq '')
                {
                    $fentry = $subentry.Properties() | where { $_.Name -eq $field }
                    # empty - what to do?
                    if ($fentry._type -eq [string])
                    {
                       $subentry.($field).Value = ""
                    }
                }
                else
                {
                    try {
                        $subentry.($field).Value = $child.InnerText.Trim()
                    } catch 
                    {
                        write-host($group + "..." + $field)
                    }
                }
            }
        }
    }
    

    [void] _load_scp($node, $sysconfig)
    {
        if (($sysconfig._alias -ne $null) -and $node.tag -ne $sysconfig._alias)
        {
            write-host(node.tag +  " no match to " +  sysconfig._alias)
        }
        foreach ($attrib in $node.Attributes)
        {
            $sysconfig.add_attribute($attrib.Name, $attrib.Value)
        }
        foreach ($subnode in $node.ChildNodes)
        {
            if ($subnode.NodeType -eq 'Comment') 
            {
                write-host ($subnode.InnerText)
                continue
            }
            # Component!
            $entry = $this._get_entry($subnode.FQDD, $sysconfig)
            if ($entry -eq $null)
            {
                write-host('No component spec found for ' + $subnode.FQDD)
                continue
            }
            $parent = $null
            if ($entry -is [ArrayType])
            {
                $parent = $entry
                $entry = $parent.find_or_create()
            }
    
            foreach ($attrib in $subnode.Attributes)
            {
                $entry.add_attribute($attrib.Name, $attrib.Value)
            }
            $this._load_child($subnode, $entry)
        }
    }

    [object] parse_scp($fname)
    {
        $tree= [xml](Get-Content $fname | Out-String)
        $sysconfig = [SystemConfiguration]::new(@{LoadingFromSCP=$True})
        # Do a pre-commit - to save original values
        $sysconfig.commit($True)
        $this._load_scp($tree.SystemConfiguration, $sysconfig)
        $sysconfig._clear_duplicates()
        $sysconfig.commit()
        return $sysconfig
    }
}

$scpparser = [SCPParser]::new('..\omsdk\omdrivers\iDRAC\Config\iDRAC.comp_spec')
$sysconfig = $scpparser.parse_scp('.\config.xml')
