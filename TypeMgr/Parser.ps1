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


class XMLParser
{
    hidden $config_spec
    XMLParser($cspecfile)
    {
        $this.config_spec = {}
        if (($cspecfile -ne $null) -and (Test-Path $cspecfile))
        {
            with open(cspecfile) as f:
                $this.config_spec = json.load(f)
        }
    }

    [object] _get_entry($comp_fqdd, $sysconfig)
    {
        foreach ($i in $this.config_spec)
        {
            if ('pattern' -in $this.config_spec[$i])
            {
                if ($this.config_spec[$i]['pattern'] -match $comp_fqdd)
                {
                    if ($i -in $sysconfig.Properties())
                    {
                        return $sysconfig.$i
                    }
                }
            }
        }
        return $null
    }

    [void] _load_child($node, $entry)
    {
        foreach ($child in $node)
        {
            if ($child.tag -eq 'Component')
            {
                $subnode = $this._get_entry($child.get('FQDD'), $entry)
                if ($subnode -eq $null)
                {
                    write-host('No component spec found for ' + $child.get('FQDD'))
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
    
            $attrname = $child.get("Name")
            if ($attrname -eq $null)
            {
                write-host("ERROR: No attribute found!!")
                continue
            }
    
            if ('.' -notin $attrname)
            {
                # plain attribute
                if ($attrname -notin $entry.__dict__)
                {
                    $entry.__setattr__($attrname, [StringField]::new($child.text, $entry))
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
    
            $match = '(.*)\.([0-9]+)#(.*)' -match $attrname
            if ($match -eq $false)
            {
                write-host($attrname + ' not good ')
                continue
            }
    
            #(group, index, field) = match.groups()
            #if group in entry.__dict__:
            #    grp = entry.__dict__[group]
    
            #    subentry = grp
            #    if isinstance(grp, ArrayType):
            #        subentry = grp.find_or_create(index=int(index))
    
            #    if field not in subentry.__dict__:
            #        field = field + '_' + group
            #    if field not in subentry.__dict__:
            #        subentry.__dict__[field] = StringField(child.text, parent=subentry)
            #        logging.debug(field+' not found in '+type(subentry).__name__)
            #        logging.debug("Ensure the attribute registry is updated.")
            #        continue
            #    if child.text is None or child.text.strip() == '':
                    # empty - what to do?
            #        if subentry.__dict__[field]._type == str:
            #            subentry.__dict__[field]._value = ""
            #    else:
            #        try:
            #            subentry.__dict__[field]._value = child.text.strip()
            #        except Exception as ex:
            #            print(group + "..." + field)
            #            print(subentry._state)
            #            print("ERROR:" + str(ex))
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