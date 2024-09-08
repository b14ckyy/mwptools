#!/usr/bin/ruby

# Extract heading & gps_course for analysis
# MIT licence
include Math
require 'csv'
require 'optparse'
require_relative 'inav_states_data'

module Poscalc
  RAD = 0.017453292

  def Poscalc.d2r d
    d*RAD
  end

def Poscalc.r2d r
    r/RAD
  end

  def Poscalc.nm2r nm
    (PI/(180*60))*nm
  end

  def Poscalc.r2nm r
    ((180*60)/PI)*r
  end

  def Poscalc.csedist lat1,lon1,lat2,lon2
    lat1 = d2r(lat1)
    lon1 = d2r(lon1)
    lat2 = d2r(lat2)
    lon2 = d2r(lon2)
    d=2.0*asin(sqrt((sin((lat1-lat2)/2.0))**2 +
                    cos(lat1)*cos(lat2)*(sin((lon2-lon1)/2.0))**2))
    d = r2nm(d)
    cse =  (atan2(sin(lon2-lon1)*cos(lat2),
                 cos(lat1)*sin(lat2)-sin(lat1)*cos(lat2)*cos(lon2-lon1))) % (2.0*PI)
    cse = r2d(cse)
    [cse,d]
  end
end


def list_states iv
  NavStates.get_states(iv).each do |k,v|
    puts "%2d : %s\n" % [k,v]
  end
  exit
end

def get_states_for_fw bbox
  gitinfo=nil
  File.open(bbox,'rb') do |f|
    f.each do |l|
      if m = l.match(/^H Firmware revision:(.*)$/)
        gitinfo = m[1]
      end
    end
  end

  if gitinfo.nil?
    abort "Doesn't look like Blackbox (#{bbox})"
  end

  iv=nil
  if gitinfo and  m=gitinfo.match(/^INAV (\d{1})\.(\d{1})\.(\d{1}) \((\S*)\) (\S+)/)
    iv = [m[1],m[2],m[3]].join('.')
  end

  inavers = nil
  if iv.nil?
    iv ="0"
  end
  inavers =  NavStates.get_state_version iv
  return inavers
end

idx = 1
llat = 0
llon = 0
minthrottle = 1000
states = []
allstates = true
plotfile=nil
outf = nil
rm = false
thr = false
ls = false
delta = 0.1
svgf = nil
pngf = nil
decl = nil

ARGV.options do |opt|
  opt.banner = "#{File.basename($0)} [options] [file]"
  opt.on('--list-states') { ls=true }
  opt.on('-p', '--plot', "Generate SVG graph (requires 'gnuplot')") { |o| plotfile=o}
  opt.on('--thr', "Include throttle value in output") { thr=true}
  opt.on('-o','--output=FILE', "CSV Output (default stdout"){|o|outf=o}
  opt.on('-i','--index=IDX', "BBL index (default 1)"){|o|idx=o}
  opt.on('-t','--min-throttle=THROTTLE',Integer,'Min Throttle for comparison (1000)'){|o|minthrottle=o}
  opt.on('-s','--states=a,b,c', Array, 'Nav states to consider [all]'){|o|states=o ; allstates=false}
  opt.on('-d', '--delta=SECS', Float, "Down sample interval (default 0.1s)") {|o| delta = o}
  opt.on('--declination=XX.X', Float, "Declination (implies --simulate-imu") {|o| decl = o}
  opt.on('-?', "--help", "Show this message") {puts opt.to_s; exit}
  begin
    opt.parse!
  rescue
    puts opt ; exit
  end
end

bbox = (ARGV[0]|| abort('no BBOX log'))
inavvers =  get_states_for_fw bbox
stcount = NavStates.get_states(inavvers).key(:nav_state_count) -1
if ls
  list_states inavvers
end

if allstates
  states=*(0..stcount)
else
  states.map! {|s| s.to_i}
end

cmd = "blackbox_decode"
cmd << " --index #{idx}"
cmd << " --merge-gps"
cmd << " --unit-frame-time s"
cmd << " --stdout"
unless decl.nil?
  cmd << " --simulate-imu --declination-dec #{decl}"
end

cmd << " " << bbox

if outf.nil? && plotfile.nil?
  outf =  STDOUT.fileno
elsif outf.nil?
  ext = File.extname(bbox)
  if ext.empty?
    outf = "#{bbox}-mag.csv"
    svgf = "#{bbox}-mag##{idx}.svg"
  else
    outf = bbox.gsub("#{ext}", '-mag.csv')
    svgf = bbox.gsub("#{ext}","-mag##{idx}.svg")
  end
  rm = true
  pngf = svgf.gsub('svg','png')
end

IO.popen(cmd,'r') do |p|
  File.open(outf,"w") do |fh|
    csv = CSV.new(p, col_sep: ",",
		  headers: true,
		  header_converters:
		  ->(f) {f.strip.downcase.gsub(' ','_').gsub(/\W+/,'').to_sym},
		  return_headers: true)
    hdrs = csv.shift
    cse = nil
    st = nil
    lt = 0
    ostr = %w/time(s) navstate gps_speed_ms gps_course attitude2 calc/.join(",")
    if !decl.nil?
      ostr << ",heading"
    end
    if thr
      ostr << ",throttle"
    end
    fh.puts ostr
    csv.each do |c|
      ts = c[:time_s].to_f
      st = ts if st.nil?
      ts = ts - st
      if ts - lt > delta
        lat = c[:gps_coord0].to_f
        lon = c[:gps_coord1].to_f
        if states.include? c[:navstate].to_i and
	  c[:rccommand3].to_i > minthrottle and
	  c[:gps_speed_ms].to_f > 2.0
          mag1 = c[:attitude2].to_f/10.0
          if  llon != 0 and llat != 0
	    if llat != lat && llon != lon
	      cse,distnm = Poscalc.csedist(llat,llon, lat, lon)
	      cse = (cse * 10.0).to_i / 10.0
	    end
          else
	    cse = nil
          end
          ostr = [ts, c[:navstate].to_i, c[:gps_speed_ms].to_f, c[:gps_ground_course].to_i, mag1,cse].join(",")
          if !decl.nil?
            ostr << ",#{c[:heading].to_f}"
          end
          if thr
            ostr << ",#{c[:rccommand3].to_i}"
          end
          fh.puts ostr
        end
        llat = lat
        llon = lon
        lt = ts
      end
    end
  end
end
if plotfile
  fn = File.basename bbox
  pltfile = DATA.read % {bbox: "#{fn} / ##{idx}", svgfile: svgf}
  fn=7
  if !decl.nil?
    pltfile.chomp!
    pltfile << ", filename using 1:#{fn} t \"Mag\" w lines lt -1 lw 3  lc rgb \"#807fd0e0\"\n"
    fn += 1
  end
  if thr
    pltfile.chomp!
    pltfile << ", filename using 1:#{fn} t \"Throttle\" w lines lt -1 lw 3  lc rgb \"brown\"\n"
  end

  pltfile << "set terminal pngcairo background rgb  'white' font 'Droid Sans,9' rounded\nset output \"#{pngf}\"\nreplot\n"

  File.open(".inav_gps_dirn.plt","w") {|plt| plt.puts pltfile}
  system "gnuplot -e 'filename=\"#{outf}\"' .inav_gps_dirn.plt"
  STDERR.puts "Graph in #{svgf}"
  File.unlink ".inav_gps_dirn.plt"
end
File.unlink outf if rm

__END__
set bmargin 8
set key top right
set key box
set grid
set termopt enhanced
set termopt font "sans,8"
set xlabel "Time(s)"
set title "Direction Analysis %{bbox}" noenhanced
set ylabel "Heading"
show label
#set xrange [ 0 : ]
#set yrange [ 0 : ]
set datafile separator ","
set terminal svg background rgb 'white' font "Droid Sans,9" rounded
set output "%{svgfile}"

plot filename using 1:3 t "GPS Speed" w lines lt -1 lw 2  lc rgb "red", filename using 1:4 t "GPS Course" w lines lt -1 lw 2  lc rgb "purple" , filename using 1:5 t "Attitude2" w lines lt -1 lw 2  lc rgb "green", filename using 1:6 t "Calc" w lines lt -1 lw 2 dt 2 lc rgb "orange"
