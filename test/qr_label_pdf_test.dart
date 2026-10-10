import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/print/print_service.dart';
import 'package:inventory_app/core/share/share_origin.dart';
import 'package:pdf/pdf.dart';

/// Precomputed 80×80 black PNG (~300–500+ bytes depending on zlib).
final Uint8List _samplePng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAwS0lEQVR4AQFA'
    'ML/PAMXXFIT4z5v0t29HkEcwgEueMiWp8TO13qFo9OKFHwcvzAD8qnymIGFx'
    'ekjlLimj+jealT+qaJPjLsWie5ReYF8QhfMjLUJMEynIjXhu1ozm/LYqpjv5'
    'q2F8CIo7cL5XqtofM0pwFyUNP2A9yC69OxILY14/9WsfC9kzhSNxJJqz31wf'
    '7xQzyGaFt/BWaB1RUq+APOJZBvHRn7bGgE4G6iirF49Feva0k7dDnsbUKQBi'
    'q1F6cuXB1BDN1hdU5CCEUADk+QAT/aaf7xnUYCpCB83VoQFtBwEyYTxlmo9d'
    'M/PLKQuM5zuDRLE6T44JFRRphKG7Ff3q3r5basCVBEZNiqqsvC+tEhWKU0yU'
    'uMpCljr0ehidWySazqiZ1Dcy9vKsrz/1O/7aE5qrT1XALCErZXEfxQQyyZTl'
    '+m/YKrxwhVXcYrc6IA7nZzz+y4NqFW5KNWXqwblNNflLz9j9pf//Z3AErqKk'
    'EkuDT8KW8CErFCFzQhSZB+WpUkzrvsMRLifaaZQA1fbGdwoAXZqCqiH8hpvQ'
    'xMQfU0F6kqscEvbVSPspTbTSEu7F6hgz8U0KEEOlNbFjxPs4Hu+sP5dBxpY+'
    'YBPI475h6bYmFhT4gg1udS/XnDpK2tgrNdQgMtRPD+Tc1Q/+poEotCQ+tw+w'
    'slsFdrskSWoBaD8DlrwMd0hf6Dn0sIRCDmq5q/KVl6deKTSdUMBLQHKhfHle'
    'lb7WF0MKySclQ9eZ1UjYmLUrf+O9HcDRBNWk4Wi+lvEuXjeNOU7kzF7XAN1Z'
    'fuiuSLXsLPdolgDl7ANvmDqaT9nxL/52z48LPYoUAIPLyuM0gbWRZCsSJIac'
    'rjx/UyLUlJBEazXSzo6V4r5GUD89w83vR5m18tRv9Pqi/B7jmUn9Gm4NtfHI'
    'BSIpygO4FTsBipV0SJNhNd7rqcRWqdfeS+VLoUJqX+Oyx9r7x3Bk4GgZxhF3'
    'K1+6HVh3mCyRtNLqG9zo+oLzbqyIFRYaU7MBlANHINtxy3HoYq00K6Ol6aaC'
    'DhZhvClrsWBngACan8SC9rB6FpwlBOv94BjT/OvhPCspezJO023hJ9rJFFx/'
    '+nBBjrSj3jaSZ5fi7IWLdgg8MljUf2+RA9sZPsSLPLd1kHF6IZ2nd7/1kldG'
    'B6e7DELKT1onRWn+bXhDd8S0Q/83Dbf66Z4GcFP99qAohEbNYaKVxB5qE6F/'
    'r+FzhbBTnAi2HU20C/sfDHsXBnOnIh+w2EVu5d5It59aqNHDBNGH7BU+0cdX'
    'AUZLKKh5Wn4LVlYo2jXqTBSBrsANEv4ALbeVTep4tlPPrIr8yQefk/ARhhPp'
    'yj3Osf0aCosRgpRqrsWAajuofLRTTqkEGk+wuZWWpf3O3FcASBbiQK4E9YNg'
    'I9mOWVYgUDjE3oifkQbbj4Sir2HdSANPxLjtEtJ0CLlRY7X+CX97jF7XJ+V5'
    '5jNgVOEh2sqLgd+2py6dD/wFgGfLxd/HE+61QI6nDMvyRRUpsbgCI2E48Rah'
    'DKHJQIzQSEvOnB5TQET2FxbGXLAqKVmHZ4WngYTpT+VOE1oRAKEkYul66lGq'
    'RfMdKq8BKDXatOerwbk8RaILXUAJrGIW0x+fxxpWtyfRG+G1gp7o01wP6Idh'
    'xiC3MT8Nswpazgal6f3zKRrNhg4xKaq3MvEQTpISAMCsUEtSWVF8qAz3yxZz'
    'e5CoV3m0c1PX7bpGxQZTAsdYTAkMpQETGDlLTsIN1t+qfka6bswlQtCzMdzf'
    'ffHDc8p69ssjgY2+C/J5jRSkyDYYScgN18ndNevsUlau8tJRkTm8sEm38htk'
    'g1qmlwDCFZXcEdKJwGqxREM4tlQP3MvtJifZRlZOalR0D0X8tpOrPNGGUa+p'
    'SsCceMGxx/Gc0dAyTksCNmg4iFbAKxIFO7n2ojfnvIH5dVEnVg1V0Wrgz4cK'
    'RMZX4RvALM+rd+kU9TSJ+8nyh1x1ulGaSekjI/TJ0S+H9nU4l0i4MEYdRmUD'
    'EM/7NvKxrzECe3T+n4xzBP21ri4nnNhzvMNKdpNm9reQxEI9zbXxdb+33Y63'
    'zZA19ZU95E6wfF+t/3U4xMcA7exwzJ/5d6EAL/GiyXTcGBTQL4Zmp1s5XLoO'
    'dxYEwwJCO2Yp7mUA1CJad3TUw/MA32vDFYkOsbys6EQvgDQ0iwxIRcJqo2fX'
    'PTbzP+XwW+itQdWCwSird+h/s/bSDOQDz+Ry23uB9PNIdOGRuPhMLGCZPh5P'
    'rxKrUu/HYNL+YlXIGK1gp13eTfxt4RB8+aJkABYfRHzicjfZkq38YlO+tuDI'
    '4KLvIktwOk/J7Wu8FwrPaizT0msCRfqewiEo/AdoANa4nyoLeg68Tu6EOOSO'
    'cMPErXSHLRZPofgg9d6jxQw73kRIDzzcfhCLh8Q7sJW/YR6tB1L9C4SpRrAy'
    '1SKANSZB+BFysTFvWnXMZ+CyUImyZm7uoEGNACqnnaURKweVOlWMZ7HlLdTR'
    'PintpVmXe9+SEAsEiSegopMYf0eEHMbWj3OBoPrlPti/Vhp29MQPeimdMl1B'
    '4Ae50z9+/5CJztzxHVS2Z39NcZpKX4ANXHfVUHxBVn6ZCutmH9JVw8ZsxQD8'
    'NEAsBSkFfMrmjdOwyoQnUHxrFxsi5H/mRJQGS7O3u5iBRAv1Zsut8prhR/OX'
    'qbLCys2YeGDcbodVR/OuhN2a6Rpjg+ojCWc0gwBuXli4iQQIClWeeMn/ubUs'
    '3TsMWAeLtGrEZKNeW/5N0HQBG98QRSvWnqlgH61GoYz49qmKJ+pRN4TP5ddR'
    '1kA5OV/2ljPZho04tiYEFAdGPtDF9g2gRyvIcxhr0w4YzEOY0M8c5EpBalYt'
    '8JOJgWzOBBojBZEAT0hEOqoDpUqpICy+aoHmqfjwKymh4MTO9dolcEnMoEsk'
    'SU8RxDsiiZq09M2j7rB2E8S7rwN/J/M4vN58DDkUtxS7XK6J+PfWAHj0sFIW'
    '9VTFk/dtDehY4qGn3EnbyHm8w5d7bIJ7vul5rEqkfEmDWDrk9Whct38t/muW'
    'x4tntdChChZiZFPqKYCT+dagxRs6HqtRiOCe1Pa/cC0pLgipMXgKFTCfLshB'
    'ZY6XUV5zRkJ0hP2bSopoKEXQXWUIs/VAAIopjnACSWoB1kFK+BWjcFnpouJ2'
    'jGAzs/qLtJBvksghWcA6MEbrSdiFY1ojh+GnwBqwx8RATRGc49Rr72jILDHN'
    'Pu5VEGd3ezDB0CNsZW/7LmIzQmPcyobxDrOwaRFl4W5sA0l56PEujZTIqJgt'
    'P/69LXVF0XoJ+JBJvUo7pKMmuGJml9nByhJJ4SeTT2D6s09M24dsO1BH4thb'
    'E5nwK7syM/19FQ8s7oWDwFN5PlH+fAZzSUlPWiI2jzCK74TWFQAmSOcesaqC'
    '0McLl3tsLUl+beejBYDXQqnGZpgw44p5hpwrvErmDcXlGpLZ72NSA4g2xYNl'
    '+PGHzkP+iVgHaq2FNw/fnqViqdJBP3+38eJYtdrf0bo2LOdDMQfF9XnJMdcd'
    'l1eajj+sAEkAL62s52V8v+yFV+bMBzQCNqhqnzqaLzSTH304VONUVO6EVeEN'
    'wQg+M54qw2qDxHXtvF/ZBNd3kbGg8u+BsItTX3HspQu+8pJ+CjTrXWXHqUQQ'
    '+9Pv4bwABmVoIvtDLM+OaijbC/SvAWWX1uWRIBMsscLTw3aQ+M0A3pP4Tszc'
    'yprwvZvWV7ET2eDhniF0qXbADK1PXf4jMloQdVsF39xblMvhnxNR9VA2O/KQ'
    'nJrIEIip7CIelnDonmnBItkUFS68A5aeHQAQFk9W8ClHCkU0JyE7ZzP53Sk6'
    '8uRWNEa+2EIpEX8wwb6lyJ17Lk7PupG0vwoEAEmDa0ZfO/r3QI2FRxRYs6Vm'
    'MP1KgKRhO3y0zDSMxrYQqXbJABHXilGGF4koq9UDiHRbgb06V/5mJdCSFYQC'
    'D1GoWM93ZRBh6Oarsbo7CNa6X/V0xQdg/dPIUk7bw+NtgSBRAZpeMk6AWsuD'
    '16TZ++09gKGDgZHAC/9n2IvQEgvUK44ND/zHs/Hj814Mtmud3CJwMVToQf6h'
    '4U/6gfuucha4h8kxnUJHSiCuYxYN+vEnGUfuRYQpmrZC770VqDQzOJydu1wD'
    '88/PbS7ViPjd/MBK22nZYokkRu6kuZXmr31T7EGucAD+TzHjolksoVOLtjs5'
    'waSnnqoAYJpfVlHzeyiENhrBLcjt+EhIHTlNPc4wkCkzb5rOWOeIrFnOhVpS'
    'K2y36S6p2ZrqHEeyWf9zdiFA4d4yuHM9pURmeaH+r/aKlwlci2Q4n+FZOBjp'
    'wNairHSp/UoN9kcAKwlGOBykn2MgGHVauMS81mvIFHID5AXUTmYgQqKPluev'
    '0/uoiJvjqs2rzo8Hbe+YzttCW/RhV2InilNe+D72f95eOxsTLjBGS2u3uzMA'
    'McD6QKtocuOSMEfWMGBCW4iNplbkrDMuygUfYK/ef6naP6gh9vyYfcQesKlW'
    'LY3qA1FIrOgix4vvkQ7PDOk4Q5momE/64wOmT9QNmFtQKNfnRtetQ7hWKi98'
    'OWf0Yg7AqIe1geITn+TdcvIHyqxtspZTWo9mPLTBT5qCVc8OJ1/H0ignfyJu'
    'pecyVlEY4IVtH/wlCBhgV/xmlCxMvgCrnnObBtO1JKiPsTOZTLQTB80E3Xfc'
    '7pYCWegiBxYuQcnEAFlwNw8Uyc+QV8INo9dmtn0Q1PwYZq3qXmRsEmY9lqWo'
    'nElc1I0cwzj+U8Jx0cZB4rkXdG7M+HIoOE5Umw6jOkNc1YMGu0YWbuOK1R5/'
    'iGKsNYn7vpYdhze3kWOud3tmYME+gFaxyA0W3jiCZpkrNdi0W0s+k5ZZ+JZ+'
    'eyf0Yrfaiac0R+2zQiDrzfajn/dIkRfSIe1aIjnJdpU22ZcPGc7TvHR9Uzc7'
    'Spe3+H7dTF+uXAurTDShfjQ19PySqy5qFQDOhK5wroUh5kETMeCPq4LjCa+k'
    'fLS5t8BnCMmdzQs8oAzeSS9AGZVkuXwqct2ikgoh64zDbVLnBVABVRkvvRty'
    'c/6Cn7+g/hl8Qm12Mkc2FS7e6ObKB6NrQJmWzRnqfsmHnT2ggojn5DSfpSff'
    'rgM3qDVkAgkJnuw4Cv95jJqHZs3k9J2pB5Y2ri5OxemGso5xXejuhPMwKlga'
    'gLiquB3ErlmR8xabo4qjJrIK5Vi3lof7AORQfLF3OhjC48ESpg0ABuuAbFru'
    'NMwchzVGHQWD2JEiqvath6t2GHniCcOjFWc6fA+gTHv8/N1c5IZYE7iXrox1'
    'yAIeM0WpVAkVU08oR01f0McJvZOwCHkFvLyvLL27IdFguIFMbF5FOaMxVLeC'
    '74bkXsrWuDGiTIRbrOUpv7+JtEzTaWZQ69p9ALtFD+HRMBrGlGbcAXXO+PzZ'
    'zs8fnlpVpD7mUcd0QIIJ6qD1snCfDvtGimm/B5LcdANwxkSBZkDH9bjwRQ/K'
    '2LCeSJT/AIXLe+xnXf7pE9Fnldk1nopTTWudQlOxa1EeNUCBkpFfH46+N9OF'
    'q4U3HA+u2feidT3Z1yqAsEwUBEDFug6+q8w4NWJspc5JFSoQtWrSO9JqrS40'
    'Rot4V27E3mVoBY/WbjS5qoB3/2waN4fdMxMzp6k6kDJ7myExyPVMpnNCeUYU'
    'G+/0eNl+bzGqWZc05eZn84b1YedRbc6z3IbHVUP6OHiwjQOc5GzKc5ShDLgR'
    '2gwLGBvQmeepDcM214wWrRYfsgA8BzIRbNKPMzdcPk96dveFzGga+SZ0Qsnq'
    'IX50PE/e+9eDYhLHT/xHGJ3F9enXqnYgmXmum3rei5XCpaNqMJuZYzR80VOh'
    'bNbtfYy6yCHz4TFVPYiHBMfJZQxTHtTZqtrCFIjyBywSTXlUqtlHlfl+JolL'
    'Y35EBg7ijZoKw+5VE1UEzLUuoA3sdoTBHt3m+lRuODBvzKSNdh6jjixeN+sL'
    '9LWA3lgTWlLcZZkaG3UMvYPokI6pv0Ii4ToxTlSt1G8AgLS1ggUg1zjX6yUz'
    '6UvDXtERsNmOkEgq46BgFnDj0UURZJFphxy7kcRDEmKZaeWWARXb3wVVNLvW'
    'donNtU8up24VycCOqGN5Evt+aY9SXud2Fih2ysvYDkqTnRZomPjDObIt6rpy'
    'FjO37GGelDIBIt5m/Wj6z/JSTwLoJdOjWymu6WL61hpQgJWW3wD8I/GV77v1'
    'I51r1u204kr2uCCDa0WSKVoC6feOXALetJrfGBAXf9guF8DwazuICVjyGCIJ'
    'AIBK4FFvenAJH+X6qU0kHxgcdM2HBP2FM0wovaNmbJl+UF61IjOS1NiCTji+'
    'yz1fGdEPi6F4CBwQC3enOS6Rg+4dNth3h4o4RTy9uYi7GyDRlbmPA0b6q3Bo'
    'JtmxJVJady2Swh22buxn7zTiZLOgrgzZNqHH2L96Q7/AxpBgaiPAal1iGKzB'
    'IDUXuk5Ut+zUrZmUpNpX50btR9G0oj4PSramaD6UuRgw4HUI6PMheSZoamW2'
    'vgOYjwStHrBU0ijdSgDp86AGvwsq7vgDfh03wTLRQfSbxQIQb1Va7FvnYQUX'
    '8PjGieitMlcU5fj1iNlzFxCnw/h4C2arY0+WXd82g8RvIL3LTNL6NYfYtrvM'
    'ttKFA2rqu20vogbA1mjZf9aiOwhqmCZtmitoUXjeppZQe/wDQ/ghAZ3iiWVH'
    'rpxFXqXOl7Pm9tRa6GuH1t/7H6/7rxml/brgIi+Rl9+u6Tmx5NMQy7MDtQvw'
    '2XAenGNvOs88G4ajrRrnTAnQgPaLcpZTfmYA+3x8irBgpkwgxGNpasNT+Joo'
    'MJ1vDhuyLOaUn/zAjXG+N6bJvTxK88SziExFJk4vgxZwtseyNvAMZ9IK09l8'
    'NSms1Jxt/OxYkvC6MgCusetNjBog51z8mk1RJHtS6xM9tKvas3Q50vgt75sP'
    'rvU8mTS+FVyfXa70csKsBr6t5Gjq1aHc2/RhUfUaYhX9AFE1U2w5PttgClLB'
    'UjzXq3PqHjg4ZTU1KygEXILqSp6WcqSOQv1VqGZ6QMnywh5dCZAyABjbEUxs'
    'nCdiCubB3/JqjCa0+9qpCBA68OFk5QOBfRV0oY0QyLtqfGChCTUZLXC1NsiL'
    'Zl/g5+pwL10/rl4lhN2baUQ3fGuegRg2S/+GRCo5Zn9xQ+dl/v00udlaANFB'
    'Q8e8ZWi3c/8Z0+0VpGehUw6m+yXOnVtzCPM7aeSUm5QDs4ouBwzvGEwrHIOf'
    'JSApchGgqu0M+c6UDXq2s6RX1mHKGg6JbZlNBs2DfgkUW+dMcqiYyCfzcImH'
    'EbuYgnedqgCVjMH4OSfVZFlqjL7i4dFr468wb/SeNQsQJHfYpDAu95f97x6e'
    '8r3yQXMZ5nt/dBGROMWs1bBIxOlB1FB2E7/s6DqohEKYEmSVhXkp6jr5pFyc'
    'NQFocblbvqp2nmMcwYOUxokrHQBDdABBk1hS+RP+n3q3PWtwTk+P9Jzkl2Kv'
    'aUXs9FNx3MeNb7Kd7EPdwOXRbBqCGfYY01kOB4FaIxCLqguZyDTC0Klpf1Tj'
    'xKDnSzGQ5ztFm3+u0qsiufwHOUsARYONQXpSsq5xeBdj+r5ZyvD9aOXEmnQ9'
    '7NSLoSwxTXP9XB7rX/ZCDXlfZBCusvaeqKulK5rPJfqis9wwPQhOu3sMKDSd'
    '2sSUpPQeeIup06ccKicUoEQamodypW1pRuXBTymHwKeolt6pYwjYSqElQ3ZB'
    '958X4+FLxit56tWnchYKjM1JcHXUWUoZezECejogFWJ+Tm+s0NEpvS2hxj6m'
    'GiYYlpgSVje/tJFX6NphfC8+1FH+6FsAMAj2TmmoGiuCAEGFqdk8yAKRmdSi'
    '/Z0bCPxBPhBrgHQ9cmGX3Zbs9NZtaAJuu1WdbxHe0a1tQpYsQh6pGUIiODgY'
    'PEvBnA/hNGEGd1QE4IeUXMmhNVU9SvJPBRGYbzyFhOb4cYrf6ZrjcNY21shm'
    'Prp8CiMK0LZmaKjfNxf73ZyLx47ET0AII1gVorrv32fNH7bE6s6BOFiSV8+D'
    'Rymf3pveAf5okWcGnTHQucO7w2ugBB401TjUrHCuq7K9S6CtK4KvjJBN08px'
    'NQB1ieVCkUaNGAR6uao75x6MTvludKouNob775zXul4uPEDOiyuUVfLUfb+M'
    'iqhZhG8ylcXMre4wI3xU6mC4iBJFA7zjkp+oWweXUw3h4z3f8ioS7t9zjUH0'
    '5Cy01J7+8uagnio6NiZ+2eEi7gtbSNKpVatQfPbIVjG7UekxTaoTOpmfjFlq'
    'yfEKicw5mL3Dk5co5XOU8gp6CTgLq9hJmBQ0Mp3vnUfbgrmE1tef9995W+iS'
    'RDFdQoCQjTaiOQJkIaIAF4j42j1Xg2N2oFwTGgBkMBn9LpxkttpRe1XoxGcb'
    '2vxM0CdYVqFS0rjY1ZRpz9DVcusrBfMSpqym95AkHyKXXot8LDBhEZvfgysQ'
    'CUJ3K9lDsydpdfIucu1Q6r9/Rzmc+B7Ob93oQMUUAX67D0MtNnBUxr5pJNFl'
    'SXfw0pm0UI2Yy796fGXTRs+QaVYVoq4RlGD5RRdUa73r2HRBXPZJChTOQx9n'
    'w2z0Ac4/he0Zofcb+EZFtOmnHyplACrTi2o7AKx4q/TIYnbIJPj4COBkAGR0'
    'nlUu+MnIWA4fJzL9MCRoyKSMHPOnMq6ECooeEc6yAvGzX31eVIzg60Zuil8/'
    'cUcqiubwsARJZLN+FgmDXxLghbc2wIqlza7AtKJim/pkGBaOtlDym8R9DEyL'
    'WM+bhwmxN7uvp3J5gQlVoWqHsH3IsMGkqd/PlXc2jiuu60v5KoNsUzyJpgiu'
    'AE649jR8xnaHGgKwiaMPAMZ76/eVQMUNb3TYIS+fJKxD2zo5bDRZYgBmvCh/'
    'jGRijChs9XkksQCcWGsJ77BzzUe7Uv0mav+58dWCWQH6hxQkELD33/k/Zxm9'
    'x4WwrUeoTD62LoqzzDWgSMeQgbdTHDhj8i+gcYLiVtto6F/4QvL2uBBrVCGg'
    'wf7LzhKiSVGGU1bsM7NyzqRG4zfLwJWq4qPF6TZA/vfiWm1YObJBXeJxctDw'
    'XBaIlTAK+43aFID0FfL2rPPYjRMkLHRgboyhWc90fC0LuwZcnc3zHkq6P5xK'
    'xNf58KVWf7AAolfQw6qn0EniKJvEZAzgcZwFBJUAH3upubMrjwtFHiOqJ4lK'
    'sH0D367by8TsOwLihTq3JfurysEzAFvSz7ARHVG1W+qU96CYM7pY/BLq3Ym9'
    'YwO+fjtpxJ1XD9a+6lvQl2OJsKDA1jnBaRJq+6x0f/v0fzhETIqiQRXAVMDt'
    'FIPvvJzH3SHW8Jt/CdWW5ffFqbNBsJ3rSWidK+pHgDtUuPQUXtZmiQSzAKOo'
    'MmIuwxXGk31AMrFrYNNS3wmMgCsBAOeXjbsU1hAVZABKLGfK0KE3M3uhKltb'
    'ePgv3XarisPjNwDRKbCWHRi+XTJ+txGpeHKiLSkcMqT/x87+r7cXQ+UvrkXT'
    'rxDj0Fi27u56tQZwJn4tW9Xhe5o3AvwdCE8a9URj3ksUaFQLaiJOAmXN9ATs'
    'zIoL4Fn4ZSVj7Q+mxTzLXcXYn1rTiD3ULLME9pfH4v229H0NuXV+nYHc346Q'
    'QAx7Rf5o/f8c8RYJM3Qne03Zm0hthOuWj0uCc9VpfRRFjAC4cYdwCSb8iW8P'
    'tsHW4b/bhY+UrZQBAbs/wLX/9btPUAnKfTZHZpqM7oRzmh9JdbSrZvc7/oFn'
    'ydEW3h/CJO1qpwtI4uvXEkJMcfslFyMOAaYhuRdu8CRmnp0PcfhbebAbH+ei'
    'wBcWCF4ke/l6HnDiBUAWVud58jCj3ON6fiKIwPfIXJOVhgJsc3bvAy3LpSL+'
    'Bbvm/RmMi2dYgYEtNtDBILKHh9vk5dHR1YE0TNYJol3MmRKlBg8GfrtnJmkV'
    'bl8AsY7WNPxN2QO3WvSqAwCIa1rJ8vtncrz3udyX34CR+jAYAonHyWIdwAum'
    '/n65qR8RceHR/o2QLAmCLjZ5pXVU+9M8tBgvTj83xPjFWaP9DGKeqHpWxZeJ'
    'NcewKYe/atyxLwH0DXwllTmB3RqBNsBrv2tN6iPAPlw55WtZoFACmd/UF2Il'
    '/Vt16+wGyTmGbcVgLTM9zmqfBzu5cA/HE0Y1RibkvG5UiSnVpJSgOnphz9FI'
    'J3pyld6T0RkfyciPDc40AAM5CpIWCcRJ+TAuGdFpfngAJTBva+G+rbIF3sfC'
    '99WnTQNva83LQvqIFtWmYAjUpVs7e6LKo6JdY3/AN8V+mQRdmrmlrNHiXbIr'
    'fru5ZhOnML+ADCuNReGNliUnRz0hfRxCrDEmR1mzRIXyjn0Blm2yZMP8p4IG'
    'Sod1m5lHfqZNLDb/rCt3llIUjQcNKJ2EotrWRTrU5rea8zTj2jnfNZzkh1XI'
    'Q9BhRlIvdWO7mJfr+xWvjpbc/wqQ2gljKHuScwAL1CtyKoYyw8E+5CwHiVO3'
    '/nhslbRiTUv+bPxeTqeMB0+FJ+B72XrlHbw22o4h/7NgLF4jD94/rqU6UKmZ'
    'OUWv019KFa2cZn+S4AKBPgZqXtAMQufP4uuj4PctiiHbZCgqsyvEydVgr/wV'
    'oUSclgRCHFWMpc6AznVkqfalWg+KS4tyzz7X6+HQ0y0EbJ4CdUNcwVdm2RRb'
    'CBBEjY6J0WUnKguZbwmmIKV1JOT39eDteTcYExzZ0fVpDKUC32r9LjUAjtBB'
    'kWEPXN1wvxxJy+nJM8SZHot1SMJYpHAfu83TDnklvlP6MjL2ufAKUlvgaf9D'
    '2pgf7lRg+CRDxTdy0fyZmj4k4NnCYUezJgmFdKErSnDQG5ADJdkiwhYiOmIg'
    '1BPOoscC+5q/8RyAAZeQf1qYcDBhd+XUOwNCVzFexmTh9GR3IZtEHNmMlYrx'
    'y4KswSYx8iJBq7sj043MXJ2bHZxN82LeFWqUjSTnUo0qpB1UWtqvqwUnS7u0'
    '2gy5ILOvSus3AOVD5MH2nvhs2KEM+dFLlqBtOGRB0xT7rYmp9zYBD76O13bG'
    'cCIyiwjKlb/PXrjAP9mqhKswW+N6YTLlVAFethyceFIqp/Uppg8UpTo01PXC'
    'so0Se4pkAP0CDgImWrnr/TDOUexfvO5TIewO7sQoGuwqOU7hUBE/Ft2/rz6+'
    '1P40HmI/WuoF/NVFCEfOOD91fgw6KhSnYbo6oUGichn6M0On9E5b+bFFFleO'
    'sa19iNOTogjzlk2EYwj6nfMEM71+egDHY8UxWoIzkFZE6dPE1HYpL9ujnf/U'
    '0rHO8ct/EDuQpBugm6f6J0ARNcl/AZd2nzPF1o0gB3OTCySITnNoeZIgKnHt'
    'Igv7QrXZw6rtRQNk3m8ljjua78Vjwn800Bsgo6udVEEOey6WEnVY39WqPPIm'
    'wfEYN1by0oZv1J9XKzLpCJRTQMVNdznGTGNT+b81CMUN0ImCpy1qtCKxEH/P'
    'LiEnnBLGDsrSMrFt/VkSI2BGieB1Xsn0PYqJ1CPCvjAySpUAcOJiaP9gZ2SI'
    '3YF5gvVG+X4OqSb2z13vEBHhcXJ3zwJ78W7EtPoqEv5+PGbvQZg6H6kUj0Yi'
    'oMLukyU08rdtCjLBYarb6a6Iy/co3YJiYUFOu/m36IGZGOKntHy3CERvJLPa'
    'V2Ipx6aEsV3FAEwwFvAKdHPsr7XesKd1Io+eQwForpHrRlI/LE7F0MgV6pnC'
    'N1totc5Bkr/W24WtCNERk+jUeEM7fctChPNhiJ5qc7l4F5qf+5fL1rU/AEGw'
    'MC9vAInd+hPRB74v6pFiqu3L/QeCuz/0ppRmcSBhrIQEcPLT36xE/UcmgWSz'
    'ppAr0izQd4FTRXhfMHeRgxMz0ZGmNSHLJlQK93Be29iSx9/5KkaRIjvm4ZHr'
    'pniBV/ME3zRVdAr+8r2z66OOcRWpL1PioUXf6ClA8Usj247uGajUFZCMBEaB'
    'SZLl4f6ZBvw+Q1g7GX/SE2XCZCdtk2rPSCo93XmfBTLr/bTSHRZhPRdMuK1j'
    'DmuKSjRMtTwPBSiMi9/0oABJvzRsal9AlUhLkx5hbVjDhphwEU5EZcEN6i/a'
    'OBa91Hs+Me5CTNzpix+pz6tgtbHS8mrpvMzLYErKcHlknQce2+80rxeTa2Bz'
    'LYwIJx5Gn8sz3XbvF1iaX4J4D7/nDzoeqDC//8fHgovDZQT9RcmImY5ExSMe'
    'v/GVcDXmVkpTsqwM/fVhJltw1kz8D8xTbiXKHQxW95yV9jwIDGSxHFzmJaSj'
    't6+LvOFo3xCru9UwZEL25pq1WRJ2kqwp6UXbLmIAIlgkichqKqc/BFNOB0FO'
    'X5VfbhRbp6fTWqKVSsjpPFqEULzhnHoW5ccEnWAufbN3XYYurFcqMSYjbsx/'
    'uDYpqajZxnXuFiMnD+GwPZE6JkpgchT5PGZm6H1Kb35jWGooeFDvO53rtktd'
    'VYCEl5t0S1wJHedX/EA/qb3fYSqJYlH8JO7ulxDKtg6OcWcqeU/E5j4nwpuF'
    '/d77WHXzHDGiVj7cJPRPy1oad1wo0VpVqYy13XeTWNgvfVpnoZUK0mqTAKbw'
    'X38KKdsdjKcSCvTJzXDRvUjUmru7JL9SJbl1whc2b0rAU204+3pgyF0DwRwM'
    'MfBZ7QpfhPKJbLTVJC0q2r50HSLixvCbmFpBEUxRlxanydhTElPdIqnyrlJJ'
    'AvlceACiZP+RYiBqh2pAAYUw9d2nZAqFjTeZywPIKVZ+dU+hw3bO26O0fpGV'
    'vlMOIMnncXitPUy7Wbl3z317/xXbHa4fvjOIAQSV5elqHL/IwzM72C91SsNv'
    'CYgmRpCJUxInwgB9I2vE4woPwoZtIDWCM+zdp2rDqBHcAtkFGwR1kmwInjhy'
    '2X2bvP3KuAYOJImQ3lLk0cyZhwuHu1ypq+y15N1d+rGXX2H3WNYIAvJRfHrm'
    '8ctD0CEJuIKpUtmofyvhDzG8FqLONVUu1to42cJeyifZptZLonPEzmYwYKIB'
    '+sHWyPneQeemiFN2WibDXPJYaJzHTlMYU2c5I5aw71gp4WjYzsBBwjVfdPrf'
    'xw+AUNH2WjqB4NmbR5bNxQ+REoF3Hu8ALroWUXB43KOEEnyeIX2jX86hJYSZ'
    'pC2mD5Xv7zHm8hgIR9JaOQF6ytMDscJI9B9twoxc2vUQ7fwuDLNSqqntvEHM'
    '1Esc0KMd9OdINE7PO7NxBr4MNbu0F9iLut0yMFGxsdY63DslmlfHTdN1k1k+'
    'mxDP2zh1UbIqSHj8quOR55PnCgcs+IiT3i+6e3LNkt2xrB7k412kf4any7WB'
    'hvH1rdY2CAmfdW9KWzD4r9K8tb7y65u8EdQMFKZvQ9PJTsqbAE5GYExjzAc2'
    'jPLRk3pRSRW/v56CIQagOREdbEFyzSqKStATbFb0AEivq9+p6aaqBmF5xFdC'
    'yhIYz4HseRnS0uMdxmzQ1gr7cEIoJSO2IxUoXp9J8ntpdKW5JoH+OT4/yH6e'
    'Xo7y22v94cMBSrqPM3EJgF2cWGS3kBMq6R0HLAZwQw22VwI8vjxCq3cVDpj7'
    '8h0U2bjRWSpnb/xZOTPgSQtOZYGfcfKlkE8kxwX7dx4Uyi/8rOy/omkVCmup'
    'oHTurQCpUE1Nq27Bs9q7vasABRTBxFN7eJdoPAXy7YfKhtHf2rMvF4eHL9jp'
    'spbcfyLxKp/+VFWhlqufYXTNTXc4AiMpKFv8hhdA1EIqm4T3Zys6wTGJS2fR'
    'fWs27GlrJMrWLbshyAxTQSkLwf7Vo0xmL8fxqMA9mrkJUD8Jh6Q/ejPv8Pt3'
    'An2Sr3OqzD9mVtAh0egORwNeO+mi44MLc9OqlIDvfN/ehsOpYjR27k0Vc3vX'
    'bdQhBdTP81TcSV9aKjcZiWEAHZUXiwmVXZ/ehgOTduxU7BPD+TiPqRHwmg5e'
    'OGnrYkGe0BtZjP0W+tiZDYN+ulvGWeGuurm4uqVNIADJDOF338SVynyl7wrt'
    'mzEG4cmjiArMPci2AeKpKQOKKPgNcHe54RsGGYbB089rnAlwUO219mnMrDBq'
    'Hx3mdTOrVUj6gbgGOnju3u/iF8Q+5SKn0UVbV7DeaTDRmtdrDnowDbXsYKcF'
    'h0JLkh9ojhqQhCcqwNL/vI40U50EUMt52VXVTTziALSbVwcfztCnhOG3Oq/F'
    'Z2S8Ar6wZX6wTMItzfhgy/7RjRRa0zjUcVrKu/4OVPm0JaVxE5UU3Ia4Iacu'
    'E8YvzudsuA3J5MRkEngclZLC7KrTwzrS6JXwawOMz2vbIaDP9AXI53cFVXtr'
    '+pbxfDBidb5u6rqfQC6ahpPMOPfu2LskzYU+hRaMMyNz5kPEZ7/vhbFE+VWT'
    'TQuOwUITxsgJY6uzx8Ski3L7pZmhXQcCglYRPMJaVfk6k2GJRrdqQnYecADC'
    'HYbk9qG+9fM2nTKAFzsfGCHtp/Wv8ZTipwjVyhhF9WiUgmH3t7L61F4y0PAg'
    'ZoPRazzfc+tzggmb0MWwnwF3hcxuI7cAReCmASkdi8TgwuBPOwfVrGuIuKTi'
    'XBnpmHKla/Wk9xWv+7SAmuOlNS9FgfGLLSZcZalbboPDYi+E7xGlWEjpZ37T'
    'C11RgDkIjsENBBFfcmQfg/jTCTi2f1B4JyDlvRa/UdhPZ2D2nv8I/saW1mSU'
    'KMaaCRo0CDFLC5cAWhhySekdu5ztfrXFp/QleibpFWGFMsmzz5W/NRAtcf4D'
    '1ml1jbcWpz0Ot1Vtp58Qfn7/Oe6Op4F9Eeqp1u1U+DV6q6q+160imUa7eP1H'
    'jypKpi+NFQftJh2zEtOID/F1KgdirL9SSsMS5Tzqph5XkFZgfc9LZa/uF1a+'
    '0jg/1rzvpzK3EOm9l0WSPNM1Llk3ZVx/0JmcAekfZensDy1GvNSPURygpJtP'
    'lVSwUHT6D+ZVgc4P0SVWyC86ZdSGSo7/AFrMZ5bMZQ0g7rpry94QL79nbb7v'
    'cvwlYr+7xeB7TDLF25+14nWKurtpKLZBJYNnNRvXs9dYVIoLfPMFzyx4cMbt'
    'fla2TkiqV8SwsqDKUOHHQeqsXxgT5YV4PwXz/XR6QmGRGcYZ6dJ4LLGjf2Lq'
    'KjUcVaP33OxII5mN4U1FrZLG9KLl5ljk1TfQRwtkaEh+675edNHEpWDQMGK8'
    'gcQBaBjzrJ2xTd2L0lRd0RzudZ6ZQmk4zGYk2Y9wmMNeCPDYLQDmUkjf0AME'
    'kquhoS99hLKCUVZ0SpT/0uROGr0YqzNoDk+ZHX4CPx9QBfhZR5eYYLEwsRSs'
    'LAqol4P1WlyH5TYm7LSURpqtK5q3rMQaVVPAFpEc1qpr3YVqVOx8odUYAHTS'
    '8X6tfKiFm8CfTzvZCMidMSJ6U6i9AN/oOVLpFHR7U/m9KY5d8jU740i/oMQ9'
    'QLTyfNDjFxFb1lXSVM8gjXRKa+ld/nIUahGLFBm6Y+RrObSQZ3lWMdO1656V'
    'Sx4EINgAvugc15XLV2DmETVCkP2y5JskcMDDqYrJRtDqyZN9n2QSVAm3wk1u'
    'zGAHNjFkPR7ThkdHQna28OW0575HkXi+BvFuWM4yEyY0kq6yKdAwVf2Jar8+'
    '3xE55P1W1y+JlghUqquL+mXlZP8kJY999rF/L6b2Rqth/UetbThtwelK8YUF'
    'DmlIfKZ2YeOU8tZ6nHnAKlEjxq8pBA9HwpPXZOU3LlM7t3yctGMTx1aQ6VPV'
    'hiuWQUJWxRbXnjDOoQ2TXREHALKV/fYLKJUaj/rhV34G/xiv4088NFvURhrR'
    '0X5Vul0qH0JJlXVfgGACAds2rWhpHguQP6a2L2amfYGMoO4FlbyzfBjUG0CW'
    '9QWdJzt4/BkYwGGg1vnAP+VINQ+LDfsxtzJAHWkSWiPwzulepmhr4eJoBwIN'
    'esIKQBBelLp3Hfes7HmpoYq4STII4BioPWlBXTA7tpFGjYEQsMLtoE5ZSNhk'
    'fS1G8oouXQxNn/57Xr8aeN/8DwQ3choJuG4b8Rh9gwBEqptx4QMEg+WqwNSn'
    'gBA1Ca734V58MSBDgtoHOf6PnXA8V0MBUTcul+/PBUR1affb2oB4DMzBSaw7'
    'fidqu99FWzsp9hupJfkvzzdxM7SQ15uHQRXRpjmnqc1mKVm0UxKhINUEykAx'
    '+m+7kgTzwhANwRl4jILtkjpr0T3orFXkjCGi8H0pj2Iu9A4Um2A4wJX7PJBa'
    'oB8wCfxtqdF7C3x4+faoXqZ69hyrGw6pCP3ZlwgkK9oIiwwHcBWoDIb80YQA'
    'DviP3v39z9Fvn/K2tlmycxw8DbBNuJbG6+X4DT7XDL2cqtUcGZpMjvqsaHQW'
    'BrVJ59VvT8zZAnTWCHN8qfo+UIf3+6aU3LFA7KepOf9ASpebzFdmaNaoTRMG'
    'DgPE33rkLw7XVOC9k+uC2AUtovBO0Pk+Pms9CDlONRN7OzksRyxhn/1ZiF9l'
    'CKlm7LUh8+m6EWMkbPRQOuUMBjlpL8oPSL6VfRM9pXVphcizcnI8T5bnt73n'
    'drqswAdNwe258JEuADa3Wxy31rNFfQr1Q916i04Y8vMZzUraPBsFJ2dDqY7n'
    'SpWprWyMsi4Sy/PrZSb0Pobuftm6zo0VPqhAWR0neHXw+TO1Mqlm5i4uPfVK'
    '8Jct50OFQ2ElFROejvZ46Ge6wm3aRiV22ZtplUtQjLc2SbzXOWm5wV9fzINM'
    'FrgMhfGkV2wiH2AM/7bJ9yEtNXgxedBtYexhBHVcBsNTG7XcI7nZB9HQs6Wr'
    '2b633K4/PtcqeT+cJ4GNYehGjwX0nDA1mjBl2oah7SrNAAAAAElFTkSuQmCC',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await rootBundle.load('assets/google_fonts/Inter-Regular.ttf');
    await rootBundle.load('assets/google_fonts/Inter-Bold.ttf');
  });

  test('vector QR label PDF builds 20 times without miss', () async {
    for (var i = 0; i < 20; i++) {
      final bytes = await PrintService.buildQrLabelPdf(
        title: 'Käse $i',
        subtitle: '3,50 €',
        qrData: 'payload-$i',
        companyName: 'Café',
      );
      expect(bytes.length, greaterThan(1000), reason: 'iter $i');
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(asciiCount(bytes, '/Type/Page'), greaterThanOrEqualTo(1));
    }
  });

  test('label text is large by default and long texts shrink to fit', () {
    expect(PrintService.labelTitleSize('Cheese'), 20);
    expect(PrintService.labelSubtitleSize('3,50 € per kg'), 16);
    expect(PrintService.labelCompanyFit('Demo Shop'), 16);
    final long = 'Organic Alpine Mountain Cheese from the Valley Farm';
    final s = PrintService.labelTitleSize(long);
    expect(s, lessThan(20));
    expect(s, greaterThanOrEqualTo(11));
    // Two lines at the chosen size cover the estimated text width.
    final textW = PrintService.qrLabelFormat.width - 20;
    expect(long.length * 0.62 * s, lessThanOrEqualTo(2 * textW + 1));
  });

  test('label PDF builds with long company/title/subtitle', () async {
    final bytes = await PrintService.buildQrLabelPdf(
      title: 'Organic Alpine Mountain Cheese from the Valley Farm Cooperative',
      subtitle: '12,90 € per kg – matured 24 months in natural caves',
      qrData: 'payload-long',
      companyName: 'Very Long Company Name Delikatessen GmbH & Co. KG',
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(asciiCount(bytes, '/Type/Page'), greaterThanOrEqualTo(1));
  });

  test(
    'image-wrap PDF builds 20 times for any paper size without miss',
    () async {
      expect(_samplePng.length, greaterThanOrEqualTo(400));
      final formats = [
        PrintService.qrLabelFormat,
        PdfPageFormat.a4,
        const PdfPageFormat(200, 200),
        PdfPageFormat(80 * PdfPageFormat.mm, 80 * PdfPageFormat.mm),
      ];
      for (var i = 0; i < 20; i++) {
        final format = formats[i % formats.length];
        final bytes = await PrintService.wrapLabelImagePdf(_samplePng, format);
        expect(bytes.length, greaterThan(800), reason: 'iter $i');
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(asciiCount(bytes, '/Type/Page'), greaterThanOrEqualTo(1));
      }
    },
  );

  test('labels-per-page grid fits every option on A4 without overlap', () {
    const margin = 8 * PdfPageFormat.mm;
    const gap = 4 * PdfPageFormat.mm;
    final w = PdfPageFormat.a4.width - 2 * margin;
    final h = PdfPageFormat.a4.height - 2 * margin;
    for (final n in PrintService.qrLabelsPerPageOptions) {
      final g = PrintService.qrLabelGrid(n, w, h, gap: gap);
      expect(g.cols * g.rows, greaterThanOrEqualTo(n), reason: 'n=$n');
      expect(
        g.cols * g.labelW + (g.cols - 1) * gap,
        lessThanOrEqualTo(w + 0.01),
      );
      expect(
        g.rows * g.labelH + (g.rows - 1) * gap,
        lessThanOrEqualTo(h + 0.01),
      );
      // Keeps the 70:100 label proportions.
      expect(g.labelW / g.labelH, closeTo(0.7, 0.001));
    }
    // 6 on portrait A4 → 2 columns × 3 rows gives the biggest labels.
    final six = PrintService.qrLabelGrid(6, w, h, gap: gap);
    expect((six.cols, six.rows), (2, 3));
    // Oct 9: 16 / 20 / 25 per A4 stay cleanly laid out — label at least
    // 35 mm wide, QR at least 22 mm (scannable), title text >= 9 pt.
    for (final n in [16, 20, 25]) {
      expect(PrintService.qrLabelsPerPageOptions, contains(n));
      final g = PrintService.qrLabelGrid(n, w, h, gap: gap);
      final scale = g.labelW / PrintService.qrLabelFormat.width;
      expect(
        g.labelW / PdfPageFormat.mm,
        greaterThanOrEqualTo(35),
        reason: 'n=$n',
      );
      expect(
        PrintService.labelQrSize * scale / PdfPageFormat.mm,
        greaterThanOrEqualTo(22),
        reason: 'n=$n QR mm',
      );
      expect(
        PrintService.labelTitleMax * scale,
        greaterThanOrEqualTo(9),
        reason: 'n=$n title pt',
      );
    }
    expect(PrintService.qrLabelsPerPageMax, 25);
    // Oct 10: every option fills complete rows (no half-empty last row).
    for (final n in PrintService.qrLabelsPerPageOptions) {
      final g = PrintService.qrLabelGrid(n, w, h, gap: gap);
      expect(g.cols * g.rows, n, reason: 'n=$n is ${g.cols}x${g.rows}');
    }
  });

  test(
    'labels-per-page PDF is a valid single image page for each option',
    () async {
      final single = await PrintService.wrapLabelImagePdf(
        _samplePng,
        PdfPageFormat.a4,
      );
      final imagesPerLabel = asciiCount(single, '/Subtype/Image');
      for (final n in PrintService.qrLabelsPerPageOptions) {
        final bytes = await PrintService.wrapLabelGridPdf(
          _samplePng,
          n,
          PdfPageFormat.a4,
        );
        expect(bytes.length, greaterThan(800), reason: 'n=$n');
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        // One embedded image, reused for every copy on the page.
        expect(asciiCount(bytes, '/Subtype/Image'), imagesPerLabel);
      }
    },
  );

  testWidgets('sharePositionOrigin never returns an empty rect', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: Size(428, 926)),
          child: SizedBox(width: 428, height: 926),
        ),
      ),
    );
    final ctx = tester.element(find.byType(SizedBox));
    expect(sharePositionOrigin(ctx).width, greaterThan(0));
  });
}

int asciiCount(Uint8List bytes, String needle) {
  return needle.allMatches(String.fromCharCodes(bytes)).length;
}
